//
//  MakeraMachine.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//

import Foundation
import Network

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

    static func == (lhs: MakeraMachineStatus, rhs: MakeraMachineStatus) -> Bool {
        lhs.state == rhs.state
            && lhs.machinePosition == rhs.machinePosition
            && lhs.workPosition == rhs.workPosition
    }

    static func parse(_ raw: String) -> MakeraMachineStatus? {
        guard raw.hasPrefix("<"), raw.hasSuffix(">") else { return nil }

        let inner = raw.dropFirst().dropLast()
        let fields = inner.split(separator: "|").map(String.init)
        guard let state = fields.first else { return nil }

        var mpos = (x: 0.0, y: 0.0, z: 0.0)
        var wpos = (x: 0.0, y: 0.0, z: 0.0)

        for field in fields.dropFirst() {
            let parts = field.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let values = parts[1].split(separator: ",").compactMap { Double($0) }
            guard values.count >= 3 else { continue }

            switch parts[0] {
            case "MPos": mpos = (values[0], values[1], values[2])
            case "WPos": wpos = (values[0], values[1], values[2])
            default: break
            }
        }

        return MakeraMachineStatus(state: state, machinePosition: mpos, workPosition: wpos)
    }
}

/// Which wire protocol the connected machine actually speaks.
/// Officially detected, not assumed — see Carvera_Controller's
/// carveracontroller/protocols/detector.py for the reference implementation.
enum MakeraWireProtocol: String {
    case smoothie = "Smoothie (plain text)"
    case makera = "Makera (framed binary)"
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

    /// Request a status report — a single realtime control byte ("?"),
    /// not a text line. Framing (or lack of it) depends on wireProtocol.
    func requestStatus() {
        guard let connection, wireProtocol != nil else { return }

        let payload: Data
        switch wireProtocol {
        case .makera:
            payload = MakeraFraming.buildFrame(ptype: MakeraFraming.ptypeCtrlSingle, payload: Data([0x3F]))
        default:
            payload = Data([0x3F])
        }
        connection.send(content: payload, completion: .contentProcessed { _ in })
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
