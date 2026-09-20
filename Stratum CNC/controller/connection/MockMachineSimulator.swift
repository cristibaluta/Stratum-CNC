//
//  MockMachineSimulator.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//


//
//  MockMachineSimulator.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//

import Foundation

/// A fake firmware behind `MachineConnection`'s "Mock Machine" entry
/// (`MakeraMachine.mock`) — lets the rest of the app connect, jog, probe,
/// upload and run a job exactly as it would against real hardware, with no
/// network I/O and no physical machine. Built for exercising the UI (the
/// connect-first prompt, the pre-run review sheet, job progress, pause/
/// resume/stop) end to end, not for firmware-accurate simulation.
///
/// Deliberately speaks the same language the rest of the app already
/// understands rather than inventing a parallel path: replies are the same
/// `"<State|MPos:...|WPos:...|P:...>"` status text `MakeraMachineStatus.parse`
/// reads from a real machine, and command acks are plain `"ok"` lines — both
/// fed back through `MachineConnection`'s own `handleLine(_:)`, so every
/// consumer downstream (`GCodeJobRunner`, `GCodeUploader`, the alert center,
/// `PanelPosition`, the canvas tool marker) is driven exactly the way it
/// would be by a real connection, with no separate mock-aware code in any
/// of them.
@MainActor
final class MockMachineSimulator {

    // MARK: - Simulated firmware state

    private var state = "Idle"
    private var machinePosition: (x: Double, y: Double, z: Double) = (0, 0, 0)
    private var workPosition: (x: Double, y: Double, z: Double) = (0, 0, 0)

    /// A running/paused/finished job's progress, in the shape `MakeraPlayback`
    /// reads. `nil` until `play` is sent — same as real firmware not
    /// reporting a `P:` field before any job has run since boot (see
    /// `MakeraMachineStatus.lastJob`'s doc comment).
    private var job: (line: Int, total: Int, elapsedSeconds: Int, isPlaying: Bool)?

    /// One tick advances a running job by roughly 1/20th of its length, so
    /// a simulated run takes about 20 seconds — long enough to see the
    /// progress bar move and pause/resume/stop actually do something, short
    /// enough not to make testing tedious. Not tied to the real file's line
    /// count (`MachineConnection` doesn't have it at this layer, and a
    /// firmware-accurate byte-percent isn't the point of a UI mock).
    private let simulatedJobLength = 200

    private var tickTimer: Timer?

    /// Fires once a second with a synthesized status line — the mock's
    /// stand-in for the real 1 Hz poll reply `MachineConnection` normally
    /// gets back over the socket.
    var onStatusLine: ((String) -> Void)?

    // MARK: - Lifecycle

    func start() {
        stop()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // One immediate line so the UI doesn't sit empty for the first second.
        onStatusLine?(statusLine())
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        if state == "Run", var job {
            job.line = min(job.total, job.line + max(1, job.total / 20))
            job.elapsedSeconds += 1
            job.isPlaying = job.line < job.total
            self.job = job
            if job.line >= job.total {
                state = "Idle"
            }
        }
        onStatusLine?(statusLine())
    }

    // MARK: - Status text

    private func statusLine() -> String {
        func fmt(_ v: Double) -> String { String(format: "%.4f", v) }
        var line = "<\(state)"
        line += "|MPos:\(fmt(machinePosition.x)),\(fmt(machinePosition.y)),\(fmt(machinePosition.z))"
        line += "|WPos:\(fmt(workPosition.x)),\(fmt(workPosition.y)),\(fmt(workPosition.z)),0.0,0.0"
        if let job {
            line += "|P:\(job.line),\(percent(for: job)),\(job.elapsedSeconds),\(job.isPlaying ? 1 : 0),\(job.line)"
        }
        line += ">"
        return line
    }

    private func percent(for job: (line: Int, total: Int, elapsedSeconds: Int, isPlaying: Bool)) -> Int {
        guard job.total > 0 else { return 0 }
        return min(100, Int((Double(job.line) / Double(job.total)) * 100))
    }

    // MARK: - Command handling (text lines — `MachineConnection.send(_:)`)

    /// Mirrors real firmware closely enough for the app's own logic to work
    /// against it unmodified: `GCodeJobRunner` only needs *an* "ok" per
    /// line, in order, and a probe/grid command's "ok" needs to lag behind
    /// a motion command's the way a real probe or leveling cycle does (see
    /// `ControllerModel.autoZeroProbe`'s doc comment on why that delay
    /// matters, not just an eventual reply) — everything else just needs to
    /// not hang.
    func handle(command: String, reply: @escaping (String) -> Void) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()

        if upper == "$H" {
            after(0.5) { [weak self] in
                self?.machinePosition = (0, 0, 0)
                self?.workPosition = (0, 0, 0)
                reply("ok")
            }
            return
        }

        if upper == "$X" {
            if state == "Alarm" { state = "Idle" }
            reply("ok")
            return
        }

        if upper == "SUSPEND" {
            state = "Pause"
            reply("ok")
            return
        }

        if upper == "RESUME" {
            state = job != nil ? "Run" : "Idle"
            reply("ok")
            return
        }

        if upper.hasPrefix("GOTO ") {
            if var job, let n = Int(trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
                job.line = min(job.total, max(0, n))
                self.job = job
            }
            reply("ok")
            return
        }

        if upper.hasPrefix("PLAY ") {
            job = (line: 0, total: simulatedJobLength, elapsedSeconds: 0, isPlaying: true)
            state = "Run"
            reply("ok")
            return
        }

        // G38.2 (probe) and G32 (leveling grid) take a real machine a
        // moment — simulated here as an artificial delay before the ack,
        // not an instant one.
        if upper.contains("G38.2") {
            applyMotion(from: upper)
            after(0.6) { reply("ok") }
            return
        }
        if upper.hasPrefix("G32") {
            after(1.5) { reply("ok") }
            return
        }

        if upper.hasPrefix("G0") || upper.hasPrefix("G1") {
            applyMotion(from: upper)
            after(0.12) { reply("ok") }
            return
        }

        if upper.hasPrefix("G10L20P0") {
            applyZero(from: upper)
            after(0.05) { reply("ok") }
            return
        }

        // Spindle, vacuum, cooling, ATC, light, M370, MDI misc, etc. —
        // nothing tracked in `statusLine()`, just needs a prompt ack so
        // whatever's waiting on it (a button, `jobRunner`) doesn't hang.
        after(0.08) { reply("ok") }
    }

    /// `MachineConnection.sendRealtime`'s mock path. `.statusQuery` answers
    /// immediately with the current status line (a real status query is
    /// near-instant); the other three just flip `state` and let the next
    /// tick's line announce it, the same way a real poll would.
    func handleRealtime(_ command: MachineRealtimeCommand) -> String? {
        switch command {
        case .statusQuery:
            return statusLine()
        case .feedHold:
            if state == "Run" { state = "Hold" }
        case .cycleResume:
            if state == "Hold" { state = job != nil ? "Run" : "Idle" }
        case .softReset:
            job = nil
            // Real Grbl/Smoothie-family firmware typically comes back in
            // ALARM after a soft reset — matches `softReset()`'s own doc
            // comment ("leaves ALARM until Unlock"), so `$X` has something
            // real to clear here too.
            state = "Alarm"
        }
        return nil
    }

    // MARK: - File transfer

    /// `MachineConnection.sendFileFrame`'s mock path — a timed success,
    /// scaled a little with payload size so a bigger file still visibly
    /// takes longer to "transfer" than a tiny one, without actually costing
    /// real time.
    func handleFileFrame(payloadSize: Int, completion: @escaping () -> Void) {
        let delay = min(0.25, 0.01 + Double(payloadSize) / 400_000)
        after(delay, completion)
    }

    // MARK: - Motion helpers

    private func applyMotion(from line: String) {
        for (letter, value) in Self.words(in: line) {
            switch letter {
            case "X": workPosition.x = value; machinePosition.x = value
            case "Y": workPosition.y = value; machinePosition.y = value
            case "Z": workPosition.z = value; machinePosition.z = value
            default: break
            }
        }
    }

    /// `line` is already uppercased by the caller. Only ever called for a
    /// `zeroCommand()`-built line (`"G10L20P0" [+ "X0"][+ "Y0"][+ "Z0"]`,
    /// no spaces, no other numbers on the line), so a plain substring check
    /// is safe — it isn't a general G-code zero-value reader.
    private func applyZero(from line: String) {
        if line.contains("X0") { workPosition.x = 0 }
        if line.contains("Y0") { workPosition.y = 0 }
        if line.contains("Z0") { workPosition.z = 0 }
    }

    /// Tiny G-code word reader — just enough to pull `X`/`Y`/`Z` numbers off
    /// a motion line for the mock's position tracking, not a general parser
    /// (see `GCodeBounds.swift` for the real one, used for the auto-level
    /// grid's extent).
    private static func words(in line: String) -> [(Character, Double)] {
        var result: [(Character, Double)] = []
        var letter: Character?
        var numberText = ""
        for char in line {
            if char.isLetter {
                if let letter, let value = Double(numberText) { result.append((letter, value)) }
                letter = char
                numberText = ""
            } else if char.isNumber || char == "." || char == "-" || char == "+" {
                numberText.append(char)
            }
        }
        if let letter, let value = Double(numberText) { result.append((letter, value)) }
        return result
    }

    private func after(_ seconds: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { action() }
    }
}