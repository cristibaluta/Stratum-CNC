//
//  GCodeJobRunner.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 19.09.2026.
//

import Foundation

/// Streams a sequence of lines to the machine, one at a time, only
/// advancing once the previous line has been acknowledged.
///
/// This rides the same line-based command channel as manual/MDI sends
/// (`ControllerModel.sendRawCommand` → `MachineConnection.send`), and that's
/// exactly its limit: real Makera hardware doesn't support running a whole
/// job this way, only small bursts like MDI or macros — see
/// `GCodeUploader`'s doc comment for why, and use that instead for a full
/// program (Roadmap 1.2).
///
/// This type only owns the *queue*. Halting motion the machine has already
/// been given is a realtime concern (Roadmap 1.3) and lives in
/// `ControllerModel.pauseJob()`/`stopJob()`, which pair these calls with a
/// feed-hold (`!`) / soft-reset (`^X`) sent via `MachineConnection`:
/// - `pause()` stops *queuing new* lines. The line already in flight is
///   frozen by the feed-hold, not by anything here.
/// - `stop()` clears the remaining queue. The soft-reset is what actually
///   cancels motion already commanded.
@MainActor
final class GCodeJobRunner: ObservableObject {

    enum State: Equatable {
        case idle
        case running
        case paused
        case completed
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var linesSent: Int = 0
    @Published private(set) var totalLines: Int = 0

    var isActive: Bool {
        state == .running || state == .paused
    }

    /// Sends one line to the machine. Supplied by `ControllerModel` so this
    /// type doesn't need to know about `MachineConnection` directly.
    private var send: ((String) -> Void)?
    private var queue: [String] = []

    /// Called once the last line has been acknowledged (state becomes
    /// `.completed`). Not called for `stop()` — an abort isn't a completion.
    var onFinish: (() -> Void)?

    /// True from the moment a line is sent until the machine acknowledges
    /// it. Tracked separately from `state` because a feed-hold can pause
    /// the runner *while a line is still in flight*: on resume we must not
    /// send the next line if the held one hasn't been acknowledged yet, or
    /// its late "ok" would advance the queue a second time and leave two
    /// lines in flight.
    private var awaitingAck = false

    func configure(send: @escaping (String) -> Void) {
        self.send = send
    }

    /// Begins streaming `lines`. Blank lines and full-line comments
    /// (`;...` / `(...)`) are skipped before sending — the firmware doesn't
    /// act on them, and every skipped line is one fewer "ok" to wait for.
    func start(lines: [String]) {
        guard !isActive else { return }

        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(";") && !$0.hasPrefix("(") }

        guard !cleaned.isEmpty else { return }

        queue = cleaned
        totalLines = cleaned.count
        linesSent = 0
        awaitingAck = false
        state = .running
        sendNext()
    }

    /// Stops queuing further lines. Resume with `resume()`.
    func pause() {
        guard state == .running else { return }
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        // If the line that was in flight at pause time is still
        // unacknowledged, its "ok" will advance the queue as usual.
        if !awaitingAck {
            sendNext()
        }
    }

    /// Clears the remaining queue and resets to idle.
    func stop() {
        queue.removeAll()
        awaitingAck = false
        state = .idle
        linesSent = 0
        totalLines = 0
    }

    /// Feed every non-status line the machine sends back through here
    /// (see `MachineConnection.onLine`). Advances the queue on each
    /// acknowledgement so lines aren't sent faster than the machine can
    /// accept them.
    func handleMachineLine(_ line: String) {
        guard isActive else { return }
        guard line.localizedCaseInsensitiveContains("ok") else { return }
        // Record the ack even while paused, so `resume()` knows whether
        // there's still a line in flight to wait for.
        awaitingAck = false
        guard state == .running else { return }
        sendNext()
    }

    private func sendNext() {
        guard state == .running else { return }
        guard !queue.isEmpty else {
            state = .completed
            onFinish?()
            return
        }
        let line = queue.removeFirst()
        linesSent += 1
        awaitingAck = true
        send?(line)
    }
}
