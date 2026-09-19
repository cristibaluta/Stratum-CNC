//
//  JogDirection.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 19.09.2026.
//


//
//  JogController.swift
//  Stratum CNC
//
//  Everything that moves the machine by hand: single step jogs and
//  hold-to-jog. Written for the stock Makera firmware, which has no
//  continuous jog (that needs the community firmware's `$J -c` plus its
//  keepalive/stop bytes) — so "hold" is emulated here with a timer that
//  keeps sending short `$J` moves for as long as a direction is held.
//
//  `$J` (checked against the community firmware's SimpleShell::jog, and
//  it's what Carvera_Controller sends for step jogs on any firmware):
//    - relative move, several axes allowed:  $J X0.5 Y-0.5 F750
//    - F is mm/min and is clamped to the slowest moving axis's max rate
//    - doesn't touch modal G-code state (no G91/G90 juggling)
//    - stops at the soft endstops when the machine has been homed
//
//  The catch with any timer approach: a move that's already been sent
//  can't be recalled. After release the machine finishes whatever is still
//  queued or in flight — roughly `leadTime` + network latency + one tick of
//  travel. That's why the hold speeds are kept modest.
//

import Foundation

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

    private let sendLine: (String) -> Void
    private let currentState: () -> String?
    private let log: (String) -> Void

    private var held: Set<JogDirection> = []
    private var timer: Timer?
    private var lastTick = Date()
    private var holdStartedAt = Date()
    private var lastSentAt: Date?

    /// How often a new chunk goes out while something is held.
    private let tickInterval: TimeInterval = 0.1
    /// Extra travel time queued on the first chunk, so the planner always
    /// has the next move ready before the current one ends (otherwise the
    /// machine slows to a stop between chunks). It's also part of how far
    /// the machine coasts after release, so keep it small.
    private let leadTime: TimeInterval = 0.1
    /// If the main thread stalls, don't try to make up more than this much
    /// travel in one chunk.
    private let maxCatchUp: TimeInterval = 0.25
    /// Safety net for a lost button-up (controller asleep, window lost
    /// focus…): a hold never lasts longer than this.
    private let maxHoldDuration: TimeInterval = 30
    /// The machine reports "Run" while it executes our own jog chunks, so
    /// for this long after we last sent one, "Run" doesn't count as a job
    /// being in progress.
    private let ownMotionWindow: TimeInterval = 2

    init(send: @escaping (String) -> Void,
         state: @escaping () -> String?,
         log: @escaping (String) -> Void) {
        self.sendLine = send
        self.currentState = state
        self.log = log
    }

    // MARK: - Single moves

    /// One relative step. Any axis left `nil` doesn't move. No feed rate is
    /// sent, so the firmware uses the moving axes' max rate — the same
    /// speed the old `G0` step jog had.
    func step(x: Double?, y: Double?, z: Double?, a: Double?) {
        guard canJog(),
              let line = jogLine(x: x ?? 0, y: y ?? 0, z: z ?? 0, a: a ?? 0, feed: nil) else {
            return
        }
        lastSentAt = Date()
        sendLine(line)
    }

    /// Rapid move to absolute work coordinates (the panel's "go to zero").
    func goTo(x: Double?, y: Double?, z: Double?, a: Double?) {
        guard x != nil || y != nil || z != nil || a != nil, canJog() else {
            return
        }
        lastSentAt = Date()
        sendLine("G90 \(CNC.rapidMove.with(x: x, y: y, z: z, a: a).command)")
    }

    // MARK: - Hold

    func press(_ direction: JogDirection) {
        guard !held.contains(direction) else {
            return
        }
        if held.isEmpty {
            guard canJog() else {
                return
            }
            held.insert(direction)
            startTimer()
        } else {
            // Joins the hold already running; picked up on the next tick.
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
        held.removeAll()
        stopTimer()
    }

    private func startTimer() {
        lastTick = Date()
        holdStartedAt = lastTick
        sendHoldChunk(duration: tickInterval + leadTime)

        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // `.common`, not the default mode: while a mouse button is held on
        // a control the run loop can be in event-tracking mode, where a
        // default-mode timer doesn't fire — the jog would send its first
        // chunk and then quietly stall for as long as the button was down.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !held.isEmpty else {
            stopTimer()
            return
        }

        let now = Date()
        if now.timeIntervalSince(holdStartedAt) > maxHoldDuration {
            log("Jog stopped: held longer than \(Int(maxHoldDuration)) s")
            stopAll()
            return
        }
        if currentState()?.lowercased() == "alarm" {
            log("Jog stopped: machine is in alarm")
            stopAll()
            return
        }

        // Travel is based on real elapsed time, not the nominal tick, so
        // timer jitter doesn't change the total distance sent: over a hold
        // it comes to holdFeed × time held (plus the one-off lead).
        let elapsed = min(now.timeIntervalSince(lastTick), maxCatchUp)
        lastTick = now
        sendHoldChunk(duration: elapsed)
    }

    private func sendHoldChunk(duration: TimeInterval) {
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

        let distance = holdFeed / 60 * duration
        let scale = distance / length
        guard let line = jogLine(x: x * scale, y: y * scale, z: z * scale, a: a * scale, feed: holdFeed) else {
            return
        }
        lastSentAt = Date()
        sendLine(line)
    }

    // MARK: - Helpers

    private func jogLine(x: Double, y: Double, z: Double, a: Double, feed: Double?) -> String? {
        var parts: [String] = []
        for (letter, value) in [("X", x), ("Y", y), ("Z", z), ("A", a)] where abs(value) >= 0.0005 {
            parts.append(letter + String(format: "%.3f", value))
        }
        guard !parts.isEmpty else {
            return nil
        }
        if let feed {
            parts.append("F" + String(format: "%.0f", feed))
        }
        return "$J " + parts.joined(separator: " ")
    }

    /// Same rule Carvera_Controller uses (`_machine_allows_jogging`): jog
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