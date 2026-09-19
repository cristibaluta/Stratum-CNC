//
//  GCodeUploader.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 19.09.2026.
//

import Foundation
import CryptoKit

/// Uploads a whole G-code program to the machine's SD card so the firmware
/// can run it from there, instead of streaming it line-by-line the way
/// `GCodeJobRunner` does.
///
/// This exists because real Makera hardware doesn't support streaming a job
/// line-by-line: waiting for an "ok" between each line is fine for
/// jogging/MDI/small macros, but a real job needs to live on the SD card so
/// the firmware can run it autonomously — buffered motion planning, no
/// per-line round-trip latency, and it survives a dropped WiFi connection
/// mid-job. `GCodeJobRunner` is still the right tool for MDI-style manual
/// sends; this is the right tool for "run this file" (Roadmap 1.2).
///
/// Two wire-level mechanisms, chosen by `MachineConnection.wireProtocol`:
///
/// - `.smoothie` (plain text / community firmware): the classic Smoothieware
///   `upload <path>` console command. The reply is
///   "uploading to file: <path>, send control-D or control-Z to finish",
///   after which the raw file bytes go straight over the socket, terminated
///   by a single 0x04 (Ctrl-D) byte. Confirmed against Smoothieware's own
///   console-commands reference.
/// - `.makera` (stock firmware's framed binary protocol): the same
///   `upload <path>` command arms the SD card, then the file body travels as
///   `ptypeFileStart` (size) / `ptypeFileData` (chunks) / `ptypeFileMD5`
///   (whole-file hex digest) / `ptypeFileEnd` frames — the ptypes
///   `MakeraFraming` already defined but `MachineConnection` previously
///   dropped on the floor. See `MakeraFraming.FileTransfer` for exactly how
///   much of that payload layout is confirmed vs. reconstructed.
///
/// Either way, the machine's ack/error replies arrive as ordinary text lines
/// over the normal channel, not as a special binary reply — real MDI logs
/// from Carvera_Controller show plain lines like "Transmission canceled by
/// Machine." / "Uploading is canceled manually." during an upload (see
/// Carvera-Community/Carvera_Controller issue #811). `handleMachineLine`
/// below is this type's half of that: `ControllerModel` feeds it the same
/// way it already feeds `GCodeJobRunner.handleMachineLine`.
@MainActor
final class GCodeUploader: ObservableObject {

    enum State: Equatable {
        case idle
        /// Sent `upload <path>`; waiting for the machine to confirm it's
        /// ready for the file body.
        case arming
        case transferring(bytesSent: Int, totalBytes: Int)
        /// All bytes are on the wire; waiting for the machine's final
        /// verdict — the framed protocol's own size/MD5 check, or the
        /// plain-text protocol's "Done saving file."
        case verifying
        case completed(remotePath: String)
        case cancelled
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Fires once, with the machine-side path, the moment a transfer
    /// finishes successfully — `ControllerModel` uses this to follow the
    /// upload with Smoothieware's `play <path>` console command, since
    /// `upload` on its own only writes the file, it doesn't run it.
    var onCompleted: ((String) -> Void)?

    var isActive: Bool {
        switch state {
        case .arming, .transferring, .verifying: true
        case .idle, .completed, .cancelled, .failed: false
        }
    }

    /// Chunk size for `ptypeFileData` frames and for the plain-text body —
    /// comfortably under `MakeraFraming.maxFrameDataLength` (8200, the
    /// parser's ceiling on type+payload+crc) with room to spare.
    private let chunkSize = 4096

    private var sendLine: ((String) -> Void)?
    private var sendRawBytes: ((Data, @escaping (Error?) -> Void) -> Void)?
    private var sendFrame: ((UInt8, Data, @escaping (Error?) -> Void) -> Void)?
    private var currentWireProtocol: (() -> MakeraWireProtocol?)?

    private var pendingContents = Data()
    private var pendingRemotePath = ""
    private var bytesSent = 0
    private var armTimeoutTask: Task<Void, Never>?

    /// Wires this uploader to a live connection without depending on
    /// `MachineConnection` directly — same reasoning as
    /// `GCodeJobRunner.configure(send:)`.
    func configure(
        sendLine: @escaping (String) -> Void,
        sendRawBytes: @escaping (Data, @escaping (Error?) -> Void) -> Void,
        sendFrame: @escaping (UInt8, Data, @escaping (Error?) -> Void) -> Void,
        wireProtocol: @escaping () -> MakeraWireProtocol?
    ) {
        self.sendLine = sendLine
        self.sendRawBytes = sendRawBytes
        self.sendFrame = sendFrame
        self.currentWireProtocol = wireProtocol
    }

    /// Begins uploading `contents` to `remoteDirectory/<sanitized fileName>`
    /// on the machine's SD card. No-op while a transfer is already active.
    func upload(fileName: String, contents: Data, remoteDirectory: String = "/sd/gcodes") {
        guard !isActive else { return }
        guard let wireProtocol = currentWireProtocol?() else {
            state = .failed("Not connected")
            return
        }
        guard !contents.isEmpty else {
            state = .failed("Nothing to upload")
            return
        }

        let safeName = Self.sanitize(fileName)
        pendingRemotePath = remoteDirectory.hasSuffix("/")
            ? remoteDirectory + safeName
            : remoteDirectory + "/" + safeName
        pendingContents = contents
        bytesSent = 0
        state = .arming

        sendLine?("upload \(pendingRemotePath)")

        // Not every firmware echoes a distinguishable "ready" line before
        // it'll accept data — the framed path in particular may just start
        // accepting `ptypeFileStart` immediately. If nothing recognisable
        // shows up within a second, start the transfer anyway rather than
        // hanging forever; `handleMachineLine` cancels this the moment a
        // real reply arrives.
        armTimeoutTask?.cancel()
        armTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !Task.isCancelled, self.state == .arming else { return }
            self.beginTransfer(wireProtocol: wireProtocol)
        }
    }

    /// Aborts an in-progress transfer. No-op if nothing is active.
    func cancel() {
        guard isActive else { return }
        armTimeoutTask?.cancel()
        if currentWireProtocol?() == .makera {
            sendFrame?(MakeraFraming.ptypeFileCancel, Data()) { _ in }
        } else {
            sendRawBytes?(Data([0x18])) { _ in } // Ctrl-X: Smoothie's abort byte
        }
        reset(to: .cancelled)
    }

    /// Feed every non-status line the machine sends back through here (see
    /// `MachineConnection.onLine`) — same wiring as
    /// `GCodeJobRunner.handleMachineLine`.
    func handleMachineLine(_ line: String) {
        let lower = line.lowercased()

        switch state {
        case .arming:
            guard let wireProtocol = currentWireProtocol?() else { return }
            armTimeoutTask?.cancel()
            if lower.contains("error") || lower.contains("not found") || lower.contains("fail") {
                reset(to: .failed(line))
            } else {
                beginTransfer(wireProtocol: wireProtocol)
            }

        case .verifying:
            if lower.contains("done") || lower.contains("ok") || lower.contains("saved") {
                reset(to: .completed(remotePath: pendingRemotePath))
            } else if lower.contains("cancel") || lower.contains("error") || lower.contains("mismatch") || lower.contains("fail") {
                reset(to: .failed(line))
            }
            // Anything else (an unrelated status echo, say) is ignored —
            // stay in `.verifying` until something recognisable arrives.

        case .idle, .transferring, .completed, .cancelled, .failed:
            break
        }
    }

    // MARK: - Transfer

    private func beginTransfer(wireProtocol: MakeraWireProtocol) {
        guard state == .arming else { return }
        state = .transferring(bytesSent: 0, totalBytes: pendingContents.count)

        switch wireProtocol {
        case .makera:
            sendFrame?(MakeraFraming.ptypeFileStart, MakeraFraming.FileTransfer.fileStartPayload(fileSize: pendingContents.count)) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.reset(to: .failed("Upload failed: \(error.localizedDescription)"))
                    return
                }
                self.sendNextFrameChunk()
            }
        case .smoothie:
            sendNextRawChunk()
        }
    }

    private func sendNextFrameChunk() {
        guard case .transferring = state else { return }
        guard bytesSent < pendingContents.count else {
            finishFrameTransfer()
            return
        }
        let end = min(bytesSent + chunkSize, pendingContents.count)
        let chunk = pendingContents.subdata(in: bytesSent..<end)

        sendFrame?(MakeraFraming.ptypeFileData, chunk) { [weak self] error in
            guard let self else { return }
            if let error {
                self.reset(to: .failed("Upload failed: \(error.localizedDescription)"))
                return
            }
            self.bytesSent = end
            self.state = .transferring(bytesSent: self.bytesSent, totalBytes: self.pendingContents.count)
            self.sendNextFrameChunk()
        }
    }

    private func finishFrameTransfer() {
        let digest = Insecure.MD5.hash(data: pendingContents)
        let hex = digest.map { String(format: "%02x", $0) }.joined()

        sendFrame?(MakeraFraming.ptypeFileMD5, MakeraFraming.FileTransfer.fileMD5Payload(hexDigest: hex)) { [weak self] error in
            guard let self else { return }
            if let error {
                self.reset(to: .failed("Upload failed: \(error.localizedDescription)"))
                return
            }
            self.sendFrame?(MakeraFraming.ptypeFileEnd, Data()) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.reset(to: .failed("Upload failed: \(error.localizedDescription)"))
                    return
                }
                self.state = .verifying
            }
        }
    }

    private func sendNextRawChunk() {
        guard case .transferring = state else { return }
        guard bytesSent < pendingContents.count else {
            finishRawTransfer()
            return
        }
        let end = min(bytesSent + chunkSize, pendingContents.count)
        let chunk = pendingContents.subdata(in: bytesSent..<end)

        sendRawBytes?(chunk) { [weak self] error in
            guard let self else { return }
            if let error {
                self.reset(to: .failed("Upload failed: \(error.localizedDescription)"))
                return
            }
            self.bytesSent = end
            self.state = .transferring(bytesSent: self.bytesSent, totalBytes: self.pendingContents.count)
            self.sendNextRawChunk()
        }
    }

    private func finishRawTransfer() {
        // 0x04 = Ctrl-D, Smoothieware's documented end-of-upload terminator
        // ("send control-D or control-Z to finish").
        sendRawBytes?(Data([0x04])) { [weak self] error in
            guard let self else { return }
            if let error {
                self.reset(to: .failed("Upload failed: \(error.localizedDescription)"))
                return
            }
            self.state = .verifying
        }
    }

    private func reset(to finalState: State) {
        armTimeoutTask?.cancel()
        armTimeoutTask = nil
        pendingContents = Data()
        bytesSent = 0
        state = finalState
        if case .completed(let remotePath) = finalState {
            onCompleted?(remotePath)
        }
    }

    /// Strips path separators and guarantees a G-code extension, so a bare
    /// document name like "From CAM" (see `NCFileDocument.load(from:)`)
    /// can't be misread as a directory or an extensionless file.
    private static func sanitize(_ fileName: String) -> String {
        var name = fileName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = "job"
        }
        let lower = name.lowercased()
        if !lower.hasSuffix(".nc") && !lower.hasSuffix(".gcode") && !lower.hasSuffix(".cnc") {
            name += ".nc"
        }
        return name
    }
}
