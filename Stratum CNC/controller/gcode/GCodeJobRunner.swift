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
/// There's still no realtime feed-hold/abort byte yet (Roadmap 1.3), so:
/// - `pause()` only stops *queuing new* lines; whatever line is already in
///   flight keeps running until the machine finishes it.
/// - `stop()` clears the remaining queue but can't cancel motion already
///   commanded to the machine.
/// Both will get sharper once that phase lands.
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
        sendNext()
    }

    /// Clears the remaining queue and resets to idle.
    func stop() {
        queue.removeAll()
        state = .idle
        linesSent = 0
        totalLines = 0
    }

    /// Feed every non-status line the machine sends back through here
    /// (see `MachineConnection.onLine`). Advances the queue on each
    /// acknowledgement so lines aren't sent faster than the machine can
    /// accept them.
    func handleMachineLine(_ line: String) {
        guard state == .running else { return }
        guard line.localizedCaseInsensitiveContains("ok") else { return }
        sendNext()
    }

    private func sendNext() {
        guard state == .running else { return }
        guard !queue.isEmpty else {
            state = .completed
            return
        }
        let line = queue.removeFirst()
        linesSent += 1
        send?(line)
    }
}
