//
//  MakeraMachine.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//

import Foundation
import Network

/// The `P:` field of a status report — progress of the file the machine is
/// playing from its SD card (Roadmap 1.4).
///
/// Community firmware emits `P:played_lines,percent,elapsed_secs,is_playing,parsed_lines`
/// (Kernel.cpp -> get_query_string(), Player.cpp -> get_progress); older
/// builds stop after the third value. Semantics, from Player.cpp:
/// - `currentLine` is a **1-based physical file line** (blank lines and
///   comments count), so it's directly the row number in a document that
///   was uploaded verbatim. While a job runs it's the last *motion* block
///   the step ticker started, and never goes backward; while suspended it's
///   the read position instead.
/// - `parsedLine` is how far the firmware has *read* into the file, which
///   runs ahead of execution by whatever's queued in the planner.
/// - `percent` is by **bytes read**, not lines executed, so it leads the
///   executing line slightly and isn't linear in lines.
/// - The block doesn't disappear when a job ends: the firmware keeps
///   reporting the last job's frozen values (`is_playing` = 0). It's only
///   absent before any job has run since boot.
struct MakeraPlayback: Equatable {
    let currentLine: Int
    let percent: Int
    let elapsedSeconds: Int
    /// The firmware's own `is_playing` flag. Note it's also 0 while a job is
    /// *suspended* — see `MakeraMachineStatus.activeJob`. Builds that don't
    /// send the flag are treated as playing while `currentLine > 0`, which
    /// is what the reference controller does for them.
    let isPlaying: Bool
    /// Only present on community firmware.
    let parsedLine: Int?

    /// `values` are the comma-separated numbers after `P:`. Returns `nil` if
    /// fewer than three, or if any isn't a plain non-negative whole number
    /// (a garbled report shouldn't be shown as progress — and `Int(_:)` on a
    /// non-finite `Double` would trap, hence `Int(exactly:)`).
    init?(values: [Double]) {
        guard values.count >= 3,
              let line = Self.wholeNumber(values[0]),
              let percent = Self.wholeNumber(values[1]),
              let seconds = Self.wholeNumber(values[2])
        else { return nil }

        self.currentLine = line
        self.percent = min(percent, 100)
        self.elapsedSeconds = seconds
        self.isPlaying = values.count >= 4 ? values[3] != 0 : line > 0
        self.parsedLine = values.count >= 5 ? Self.wholeNumber(values[4]) : nil
    }

    private static func wholeNumber(_ value: Double) -> Int? {
        guard let number = Int(exactly: value.rounded()), number >= 0 else { return nil }
        return number
    }

    /// 0...1, for a progress bar.
    var fraction: Double {
        Double(percent) / 100
    }

    /// "42:07" under an hour, "1:02:03" past it.
    var elapsedText: String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// Parsed contents of a Smoothieware/grbl-style status report, e.g.
/// "<Idle|MPos:0.0000,0.0000,0.0000|WPos:0.0000,0.0000,0.0000,0.0,0.0|R:0.0|G:0|F:0.0,6000.0,100.0>"
///
/// This text format is identical whether it arrives as a plain line or
/// unwrapped from inside a Makera binary frame — only the transport differs.
/// Confirmed against Carvera_Community_Firmware/src/libs/Kernel.cpp -> get_query_string()
struct MakeraMachineStatus: Equatable {
    let state: String
    let machinePosition: (x: Double, y: Double, z: Double)
    let workPosition: (x: Double, y: Double, z: Double)
    /// The `P:` field, when the machine sent one (Roadmap 1.4). Defaulted so
    /// existing memberwise call sites keep compiling.
    var playback: MakeraPlayback? = nil

    static func == (lhs: MakeraMachineStatus, rhs: MakeraMachineStatus) -> Bool {
        lhs.state == rhs.state
            && lhs.machinePosition == rhs.machinePosition
            && lhs.workPosition == rhs.workPosition
            && lhs.playback == rhs.playback
    }

    // MARK: - State helpers (Roadmap 1.3)
    //
    // Prefix matches rather than equality because grbl-style firmware
    // appends a sub-state after a colon (e.g. "Hold:0").

    /// Executing motion — the only state where a feed-hold (`!`) has
    /// anything to hold.
    var isRunning: Bool {
        state.hasPrefix("Run")
    }

    /// Stopped by a realtime feed-hold (`!`); resumed with `~`.
    var isFeedHeld: Bool {
        state.hasPrefix("Hold")
    }

    /// Stopped by the console `suspend` command — the firmware's SUSPEND
    /// state, reported as `Pause`. Different from a feed-hold: `suspend`
    /// waits for the planner to drain, saves position, and stops the
    /// spindle, and is resumed with the console `resume` command, *not* `~`
    /// (Player.cpp -> suspend_command; Carvera_Controller uses the same
    /// pairing). A job can be in this state without the app having asked
    /// for it, e.g. paused from the machine's own controls.
    var isSuspended: Bool {
        state.hasPrefix("Pause")
    }

    /// Either kind of pause. Which command resumes it depends on which —
    /// see `isFeedHeld` / `isSuspended`.
    var isHeld: Bool {
        isFeedHeld || isSuspended
    }

    /// Progress of a job the machine is currently running or has paused.
    ///
    /// `is_playing` alone isn't enough to decide this: the firmware reports
    /// it as 0 while a job is suspended even though the job is very much
    /// alive and resumable, so a suspended machine still counts. (A
    /// feed-hold keeps `is_playing` at 1.)
    var activeJob: MakeraPlayback? {
        guard let playback else { return nil }
        return (playback.isPlaying || isSuspended) ? playback : nil
    }

    /// The frozen numbers from the last job that ended or was aborted, which
    /// the firmware keeps reporting until the next one starts. This is where
    /// an interrupted job stopped — what a resume-from-line (Roadmap 1.5)
    /// needs. Nil if it never got as far as line 1 (older firmware reports
    /// `P:0,0,0` when idle, which isn't worth showing).
    var lastJob: MakeraPlayback? {
        guard activeJob == nil, let playback, playback.currentLine > 0 else { return nil }
        return playback
    }

    /// Anything that's neither at rest nor already halted — i.e. the states
    /// where a soft-reset means "abort what's happening" rather than "reset
    /// a machine that was doing nothing".
    var isBusy: Bool {
        !(state.hasPrefix("Idle") || state.hasPrefix("Alarm"))
    }

    static func parse(_ raw: String) -> MakeraMachineStatus? {
        guard raw.hasPrefix("<"), raw.hasSuffix(">") else { return nil }

        let inner = raw.dropFirst().dropLast()
        let fields = inner.split(separator: "|").map(String.init)
        guard let state = fields.first else { return nil }

        var mpos = (x: 0.0, y: 0.0, z: 0.0)
        var wpos = (x: 0.0, y: 0.0, z: 0.0)
        var playback: MakeraPlayback?

        for field in fields.dropFirst() {
            let parts = field.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let values = parts[1].split(separator: ",").compactMap { Double($0) }
            guard values.count >= 3 else { continue }

            switch parts[0] {
            case "MPos": mpos = (values[0], values[1], values[2])
            case "WPos": wpos = (values[0], values[1], values[2])
            case "P": playback = MakeraPlayback(values: values)
            default: break
            }
        }

        return MakeraMachineStatus(state: state, machinePosition: mpos, workPosition: wpos, playback: playback)
    }
}

/// Which wire protocol the connected machine actually speaks.
/// Officially detected, not assumed — see Carvera_Controller's
/// carveracontroller/protocols/detector.py for the reference implementation.
enum MakeraWireProtocol: String {
    case smoothie = "Smoothie (plain text)"
    case makera = "Makera (framed binary)"
}

/// Single-byte realtime controls. Unlike a G-code/console line these aren't
/// queued behind whatever the machine is doing — the firmware acts on them
/// the moment the byte arrives, which is the whole point for holding or
/// aborting a running job (Roadmap 1.3).
///
/// Byte values follow the Smoothieware/grbl convention the rest of this app
/// already assumes (`?` status polling, `$X`/`$H`, and `GCodeUploader`'s
/// Ctrl-X on cancel). Under the framed Makera protocol they travel as
/// `ptypeCtrlSingle` frames, same as `?` always has.
enum MachineRealtimeCommand: UInt8 {
    case statusQuery = 0x3F  // "?"
    case feedHold = 0x21     // "!"
    case cycleResume = 0x7E  // "~"
    case softReset = 0x18    // Ctrl-X

    /// How the command appears in the terminal log.
    var logText: String {
        switch self {
        case .statusQuery: "?"
        case .feedHold: "! (feed hold)"
        case .cycleResume: "~ (resume)"
        case .softReset: "^X (soft reset)"
        }
    }
}

/// Errors surfaced by `MachineConnection`'s send paths that aren't just
/// "the socket failed" (`NWError`) — e.g. calling a protocol-specific send
/// method while the wrong wire protocol (or no protocol yet) is active.
enum MachineConnectionError: LocalizedError {
    case notReady

    var errorDescription: String? {
        switch self {
        case .notReady: "Not connected, or wrong wire protocol for this send path"
        }
    }
}

/// Manages a live TCP connection to a Makera machine's command port (2222).
///
/// On connect, probes which wire protocol the firmware speaks before sending
/// any real commands: newer / stock firmware speaks a binary framed protocol
/// with CRC16 checksums, while some firmware (older / community builds)
/// speaks plain newline-terminated text. Sending the wrong shape gets
/// silently ignored by the firmware — there's no error, it just never replies.
@MainActor
final class MachineConnection: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var wireProtocol: MakeraWireProtocol?
    @Published private(set) var status: MakeraMachineStatus?
    @Published private(set) var rawLog: [String] = []
    @Published var lastError: String?

    /// Fires for every non-status line the machine sends back (e.g. "ok",
    /// error replies) — not fired for status reports, which update `status`
    /// instead. `GCodeJobRunner` listens here to know when it's safe to
    /// send the next queued line.
    var onLine: ((String) -> Void)?

    /// Fires for every inbound frame using one of the file-transfer ptypes
    /// (`ptypeFileStart`...`ptypeFileRetry`) instead of being silently
    /// dropped. In practice the machine's real acks/errors during an
    /// upload arrive as ordinary text through `onLine` (see
    /// `GCodeUploader`'s doc comment for the MDI trail that showed this),
    /// so nothing currently drives this off `ptypeFileRetry`'s payload —
    /// it's here so that behaviour can be added once someone can capture
    /// what the machine actually puts in it, without touching the parser.
    var onFileTransferFrame: ((UInt8, Data) -> Void)?

    private var connection: NWConnection?
    private var pollTimer: Timer?

    // Smoothie (plain-text) parsing state
    private var lineBuffer = Data()

    // Makera (framed) parsing state
    private let frameParser = MakeraFrameParser()

    // Protocol detection state
    private var detectionBuffer = Data()
    private var detectionAttempt = 0
    private let maxDetectionAttempts = 3

    // MARK: - Connection lifecycle

    func connect(to machine: MakeraMachine) {
        disconnect()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(machine.ip),
            port: NWEndpoint.Port(rawValue: machine.port) ?? 2222
        )
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.lastError = nil
                    self.startReceiving()
                    self.beginProtocolDetection()
                case .failed(let error):
                    self.lastError = "Connection failed: \(error.localizedDescription)"
                    self.isConnected = false
                case .cancelled:
                    self.isConnected = false
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        self.connection = connection
    }

    func disconnect() {
        pollTimer?.invalidate()
        pollTimer = nil
        connection?.cancel()
        connection = nil
        isConnected = false
        wireProtocol = nil
        status = nil
        lineBuffer.removeAll()
        detectionBuffer.removeAll()
        detectionAttempt = 0
        frameParser.reset()
    }

    func clearLogs() {
        rawLog.removeAll()
    }

    /// Adds a line to the terminal log that didn't come from the machine
    /// (e.g. why a jog was ignored).
    func appendLog(_ message: String) {
        rawLog.append(message)
        if rawLog.count > 200 {
            rawLog.removeFirst(rawLog.count - 200)
        }
    }

    // MARK: - Protocol detection

    /// Sends a raw plain-text probe ("echo echo\n") up to 3 times. If any
    /// reply contains "echo", the machine speaks plain-text Smoothie.
    /// If all attempts time out with no recognizable reply, we conclude the
    /// machine speaks the framed Makera protocol instead (matches the
    /// reference app's detector.py exactly).
    private func beginProtocolDetection() {
        wireProtocol = nil
        detectionAttempt = 0
        detectionBuffer.removeAll()
        rawLog.append("Detecting protocol…")
        attemptProbe()
    }

    private func attemptProbe() {
        guard let connection, wireProtocol == nil else { return }
        detectionAttempt += 1
        detectionBuffer.removeAll()

        let probe = "echo echo\n".data(using: .utf8)!
        connection.send(content: probe, completion: .contentProcessed { _ in })

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.wireProtocol == nil else { return }

            if let text = String(data: self.detectionBuffer, encoding: .utf8),
               text.localizedCaseInsensitiveContains("echo") {
                self.finishDetection(.smoothie)
            } else if self.detectionAttempt < self.maxDetectionAttempts {
                self.attemptProbe()
            } else {
                self.finishDetection(.makera)
            }
        }
    }

    private func finishDetection(_ detected: MakeraWireProtocol) {
        wireProtocol = detected
        detectionBuffer.removeAll()
        rawLog.append("Protocol: \(detected.rawValue)")
        startPolling()
    }

    // MARK: - Sending

    /// Send a line-based command: G-code, M-code, or a Smoothieware console
    /// command like "get wcs" or "config-get-all -e". Encoded according to
    /// whichever wire protocol was detected for this connection.
    func send(_ command: String) {
        guard let connection else { return }

        // Record our command in the raw logs
        rawLog.append("> \(command)")

        switch wireProtocol {
        case .makera:
            let stripped = command.trimmingCharacters(in: .whitespacesAndNewlines)
            let frame = MakeraFraming.buildFrame(ptype: MakeraFraming.ptypeCtrlMulti, payload: Data(stripped.utf8))
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.lastError = "Send failed: \(error.localizedDescription)" }
            })

        case .smoothie, .none:
            var line = command
            if !line.hasSuffix("\n") { line += "\n" }
            connection.send(content: line.data(using: .utf8), completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.lastError = "Send failed: \(error.localizedDescription)" }
            })
        }
    }

    /// Sends a single realtime control byte — not a text line. Framing (or
    /// lack of it) depends on `wireProtocol`, so this is a no-op (returns
    /// `false`) until protocol detection has finished: before that we don't
    /// know which shape the machine would understand.
    ///
    /// Everything except the 1 Hz status poll is echoed to the terminal log
    /// so a hold/resume/reset is visible in the console history.
    @discardableResult
    func sendRealtime(_ command: MachineRealtimeCommand) -> Bool {
        guard let connection, wireProtocol != nil else { return false }

        if command != .statusQuery {
            appendLog("> \(command.logText)")
        }

        let byte = Data([command.rawValue])
        let payload: Data
        switch wireProtocol {
        case .makera:
            payload = MakeraFraming.buildFrame(ptype: MakeraFraming.ptypeCtrlSingle, payload: byte)
        default:
            payload = byte
        }

        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            // A dropped status poll is noise; a dropped hold/reset is not.
            guard let error, command != .statusQuery else { return }
            Task { @MainActor in
                self?.lastError = "Send failed: \(error.localizedDescription)"
            }
        })
        return true
    }

    /// Request a status report — a single realtime control byte ("?").
    func requestStatus() {
        sendRealtime(.statusQuery)
    }

    // MARK: - File transfer (Roadmap 1.2)
    //
    // Neither of these goes through `send(_:)`: they're lower-level than a
    // line/command, only meaningful during an active upload, and each
    // protocol needs a different shape (a CRC-framed binary packet vs. a
    // completely unwrapped byte stream). `GCodeUploader` owns the sequencing
    // and calls whichever of the two matches `wireProtocol`.

    /// Sends one `ptypeFileStart`/`Data`/`MD5`/`End`/`Cancel` frame. Only
    /// meaningful once the framed Makera protocol has been detected.
    /// `completion` mirrors `NWConnection.send`'s own completion handler so
    /// `GCodeUploader` can pace chunk-by-chunk sending off real socket
    /// backpressure instead of firing every chunk at once.
    func sendFileFrame(ptype: UInt8, payload: Data, completion: @escaping (Error?) -> Void) {
        guard let connection, wireProtocol == .makera else {
            completion(MachineConnectionError.notReady)
            return
        }
        let frame = MakeraFraming.buildFrame(ptype: ptype, payload: payload)
        connection.send(content: frame, completion: .contentProcessed { error in
            Task { @MainActor in completion(error) }
        })
    }

    /// Writes bytes straight to the socket — no line framing, no Makera CRC
    /// wrapper. Only meaningful for the plain-text (`.smoothie`) protocol's
    /// legacy `upload` flow: the raw file body, then a single 0x04 (Ctrl-D)
    /// terminator byte.
    func sendRawBytes(_ bytes: Data, completion: @escaping (Error?) -> Void) {
        guard let connection, wireProtocol == .smoothie else {
            completion(MachineConnectionError.notReady)
            return
        }
        connection.send(content: bytes, completion: .contentProcessed { error in
            Task { @MainActor in completion(error) }
        })
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestStatus() }
        }
    }

    // MARK: - Receiving

    private func startReceiving() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.routeIncoming(data)
                }
                if let error {
                    self.lastError = "Receive error: \(error.localizedDescription)"
                    self.isConnected = false
                } else if !isComplete {
                    self.startReceiving()
                }
            }
        }
    }

    private func routeIncoming(_ data: Data) {
        guard let wireProtocol else {
            detectionBuffer.append(data)
            return
        }
        switch wireProtocol {
        case .smoothie:
            handleSmoothieBytes(data)
        case .makera:
            handleMakeraBytes(data)
        }
    }

    private func handleSmoothieBytes(_ data: Data) {
        lineBuffer.append(data)
        while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) { // "\n"
            let chunk = lineBuffer[..<newlineIndex]
            lineBuffer.removeSubrange(...newlineIndex)

            guard let line = String(data: chunk, encoding: .utf8) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            handleLine(trimmed)
        }
    }

    private func handleMakeraBytes(_ data: Data) {
        for frame in frameParser.feed(data) {
            if MakeraFraming.fileTransferTypes.contains(frame.ptype) {
                onFileTransferFrame?(frame.ptype, frame.payload)
                continue
            }
            guard let text = String(data: frame.payload, encoding: .utf8) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            handleLine(trimmed)
        }
    }

    private func handleLine(_ line: String) {
        if let parsed = MakeraMachineStatus.parse(line) {
            status = parsed
            return // don't spam the log with every 1s status poll
        }

        rawLog.append(line)
        if rawLog.count > 200 {
            rawLog.removeFirst(rawLog.count - 200)
        }
        onLine?(line)
    }
}
