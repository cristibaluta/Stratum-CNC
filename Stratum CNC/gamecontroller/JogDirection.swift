//
//  JogController.swift
//  Stratum CNC
//
//  Everything that moves the machine by hand: single step jogs and
//  hold-to-jog. Written for the stock Makera firmware, which has no
//  continuous jog (that needs the community firmware's `$J -c` plus its
//  keepalive/stop bytes) — so "hold" is emulated here with a timer that
//  keeps sending short relative moves for as long as a direction is held.
//
//  Each move is plain G-code, with the distance mode stated explicitly:
//
//      G91
//      G1 X0.5 Y-0.5 F750      (G0 when no feed is given)
//      G90
//
//  `$J` is NOT used: it is a community-firmware command, absent from the stock
//  Makera firmware. The `G91` ... `G90` pair is always sent together, so the
//  machine is never left in relative mode by a finished jog; the cost is that
//  it does set the modal distance mode (and, with a feed, the modal feed), so
//  a jog while a job is paused relies on the job having been in G90 (CAM output
//  always is).
//
//  The three lines go out together and the next jog is only sent once all
//  three were acknowledged (`SL.BatchSender`): the machine's input buffer is
//  small, and a G90 that is already queued runs even if the move is rejected.
//  While a batch is in flight, step clicks are summed, and a hold sends its
//  next chunk (`holdFeed × chunkDuration` long) from a one-shot timer started
//  by the acknowledgement.
//
//  The catch with any timer approach: a move that's already been sent
//  can't be recalled. After release the machine finishes whatever is still
//  queued or in flight — roughly `leadTime` + network latency + one tick of
//  travel. That's why the hold speeds are kept modest.
//

import Foundation
import StratumLink

/// The eight directions a jog panel button or game controller input can hold.
enum JogDirection: CaseIterable, Hashable {
    case xPlus, xMinus, yPlus, yMinus, zPlus, zMinus, aPlus, aMinus

    /// -1 or +1 on this direction's axis, 0 on the others.
    var unit: (x: Double, y: Double, z: Double, a: Double) {
        switch self {
        case .xPlus: (1, 0, 0, 0)
        case .xMinus: (-1, 0, 0, 0)
        case .yPlus: (0, 1, 0, 0)
        case .yMinus: (0, -1, 0, 0)
        case .zPlus: (0, 0, 1, 0)
        case .zMinus: (0, 0, -1, 0)
        case .aPlus: (0, 0, 0, 1)
        case .aMinus: (0, 0, 0, -1)
        }
    }
}

@MainActor
final class JogController {

    /// Speed while a direction is held, in mm/min (degrees/min for A).
    var holdFeed: Double = 750

    /// Sends the lines together; false while the previous batch is still waiting for its acknowledgements.
    private let sendBatch: ([String]) -> Bool
    /// Whether the previous batch is still waiting for its acknowledgements.
    private let isBatchBusy: () -> Bool
    private let currentState: () -> String?
    private let log: (String) -> Void

    private var held: Set<JogDirection> = []
    /// One-shot: sends the next hold chunk shortly before the current one ends.
    private var nextChunkTimer: Timer?
    private var holdStartedAt = Date()
    private var lastSentAt: Date?
    /// The hold chunk in flight: when it went out and how long it takes to travel.
    private var lastChunk: (sentAt: Date, duration: TimeInterval)?
    private var ackLogged = false

    /// How long one hold chunk takes to travel: its length is
    /// `holdFeed / 60 × chunkDuration`, so the speed picker sets the distance
    /// and the machine moves at `holdFeed`.
    private let chunkDuration: TimeInterval = 0.3
    /// The next chunk is sent this long before the current one ends, so the
    /// planner always has the next move ready (otherwise the machine slows to
    /// a stop between chunks). It's also part of how far the machine coasts
    /// after release, so keep it small.
    private let leadTime: TimeInterval = 0.1
    /// Safety net for a lost button-up (controller asleep, window lost
    /// focus…): a hold never lasts longer than this.
    private let maxHoldDuration: TimeInterval = 30
    /// The machine reports "Run" while it executes our own jog chunks, so
    /// for this long after we last sent one, "Run" doesn't count as a job
    /// being in progress.
    private let ownMotionWindow: TimeInterval = 2

    init(sendBatch: @escaping ([String]) -> Bool,
         isBatchBusy: @escaping () -> Bool,
         state: @escaping () -> String?,
         log: @escaping (String) -> Void) {
        self.sendBatch = sendBatch
        self.isBatchBusy = isBatchBusy
        self.currentState = state
        self.log = log
    }

    // MARK: - Single moves

    /// One relative step. Any axis left `nil` doesn't move. No feed rate is
    /// sent, so the firmware uses the moving axes' max rate — the same
    /// speed the old `G0` step jog had.
    func step(x: Double?, y: Double?, z: Double?, a: Double?) {
        guard canJog() else {
            return
        }
        // Clicks that arrive while a jog is still being acknowledged are
        // added together and sent as one move when it is done.
        pendingStep.x += x ?? 0
        pendingStep.y += y ?? 0
        pendingStep.z += z ?? 0
        pendingStep.a += a ?? 0
        flushPendingStep()
    }

    /// Total of the step clicks not yet sent.
    private var pendingStep = (x: 0.0, y: 0.0, z: 0.0, a: 0.0)

    private func flushPendingStep() {
        guard !isBatchBusy(),
              let lines = jogLines(x: pendingStep.x, y: pendingStep.y, z: pendingStep.z, a: pendingStep.a, feed: nil)
        else {
            return
        }
        guard sendBatch(lines) else {
            return
        }
        pendingStep = (0, 0, 0, 0)
        lastSentAt = Date()
    }

    /// The batch in flight ended. Call from the batch sender's `onFinish`.
    /// A rejected move stops everything: nothing queued, no hold carried on.
    func batchFinished(failed: Bool) {
        if failed {
            pendingStep = (0, 0, 0, 0)
            log("Jog stopped: the machine rejected the move")
            stopAll()
            return
        }
        flushPendingStep()
        continueHold()
    }

    /// Rapid move to absolute work coordinates (the panel's "go to zero").
    func goTo(x: Double?, y: Double?, z: Double?, a: Double?) {
        guard x != nil || y != nil || z != nil || a != nil, canJog() else {
            return
        }
        guard sendBatch(["G90", CNC.rapidMove.with(x: x, y: y, z: z, a: a).command]) else {
            log("Jog ignored: the previous move is still being acknowledged")
            return
        }
        lastSentAt = Date()
    }

    // MARK: - Hold
    //
    // One chunk is `holdFeed × chunkDuration` long. Once the machine has
    // acknowledged it, a one-shot timer fires `chunkDuration - leadTime` after
    // it was sent, and the next chunk goes out. So the pace follows the chosen
    // speed, and the machine always has about `leadTime` of motion queued.

    func press(_ direction: JogDirection) {
        guard !held.contains(direction) else {
            return
        }
        if held.isEmpty {
            guard canJog() else {
                return
            }
            held.insert(direction)
            holdStartedAt = Date()
            lastChunk = nil
            ackLogged = false
            sendNextChunk()
        } else {
            // Joins the hold already running; picked up with the next chunk.
            held.insert(direction)
        }
    }

    func release(_ direction: JogDirection) {
        held.remove(direction)
        if held.isEmpty {
            stopTimer()
        }
    }

    /// Ends every hold immediately. Call whenever a button-up might never
    /// arrive: mode change, window/app deactivation, disconnect, view
    /// disappearing, controller unplugged.
    func stopAll() {
        pendingStep = (0, 0, 0, 0)
        held.removeAll()
        lastChunk = nil
        stopTimer()
    }

    private func stopTimer() {
        nextChunkTimer?.invalidate()
        nextChunkTimer = nil
    }

    /// The batch in flight was acknowledged: schedule the next hold chunk.
    private func continueHold() {
        guard !held.isEmpty else {
            return
        }
        guard let last = lastChunk else {
            sendNextChunk()
            return
        }
        let now = Date()
        if !ackLogged {
            ackLogged = true
            log(String(format: "Jog: chunk acknowledged after %.0f ms (%.0f mm/min, %.0f ms per chunk)",
                       now.timeIntervalSince(last.sentAt) * 1000, holdFeed, last.duration * 1000))
        }
        let delay = max(0, last.sentAt.addingTimeInterval(last.duration - leadTime).timeIntervalSince(now))

        stopTimer()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.sendNextChunk() }
        }
        // `.common`, not the default mode: while a mouse button is held on
        // a control the run loop can be in event-tracking mode, where a
        // default-mode timer doesn't fire.
        RunLoop.main.add(timer, forMode: .common)
        nextChunkTimer = timer
    }

    private func sendNextChunk() {
        nextChunkTimer = nil
        guard !held.isEmpty else {
            return
        }
        if Date().timeIntervalSince(holdStartedAt) > maxHoldDuration {
            log("Jog stopped: held longer than \(Int(maxHoldDuration)) s")
            stopAll()
            return
        }
        if currentState()?.lowercased() == "alarm" {
            log("Jog stopped: machine is in alarm")
            stopAll()
            return
        }
        // The previous batch isn't acknowledged yet: `batchFinished` comes back here.
        guard !isBatchBusy() else {
            return
        }

        var x = 0.0, y = 0.0, z = 0.0, a = 0.0
        for direction in held {
            let unit = direction.unit
            x += unit.x
            y += unit.y
            z += unit.z
            a += unit.a
        }

        // Opposite directions held together cancel out.
        let length = (x * x + y * y + z * z + a * a).squareRoot()
        guard length > 0 else {
            return
        }

        let distance = holdFeed / 60 * chunkDuration
        let scale = distance / length
        guard let lines = jogLines(x: x * scale, y: y * scale, z: z * scale, a: a * scale, feed: holdFeed),
              sendBatch(lines) else {
            return
        }
        lastSentAt = Date()
        lastChunk = (Date(), chunkDuration)
    }

    // MARK: - Helpers

    /// The lines for one relative move: relative mode on, the move, absolute
    /// mode back. Nil when every axis is below the resolution.
    private func jogLines(x: Double, y: Double, z: Double, a: Double, feed: Double?) -> [String]? {
        var parts: [String] = []
        for (letter, value) in [("X", x), ("Y", y), ("Z", z), ("A", a)] where abs(value) >= 0.0005 {
            parts.append(letter + value.fixed(3))
        }
        guard !parts.isEmpty else {
            return nil
        }
        var move = feed == nil ? "G0 " : "G1 "
        move += parts.joined(separator: " ")
        if let feed {
            move += " F" + feed.fixed(0)
        }
        return ["G91", move, "G90"]
    }

    /// Same rule as Carvera_Controller (`_machine_allows_jogging`): jog
    /// when idle or paused, not mid-job. Status only arrives about once a
    /// second, so it lags — hence `ownMotionWindow` for our own "Run".
    private func canJog() -> Bool {
        guard let state = currentState() else {
            log("Jog ignored: no status from the machine yet")
            return false
        }
        switch state.lowercased() {
        case "idle", "pause":
            return true
        case "run":
            if let lastSentAt, Date().timeIntervalSince(lastSentAt) < ownMotionWindow {
                return true
            }
        default:
            break
        }
        log("Jog ignored: machine state is \(state)")
        return false
    }
}
