//
//  AppModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import simd
#if os(macOS)
import AppKit
#endif

@MainActor
class ControllerModel: ObservableObject {

    @Published var discovery = MachineDiscovery()
    @Published var connection = MachineConnection()
    @Published var selectedMachine: MakeraMachine?

    @Published var mdiInput = ""
    @Published var commandHistory: [String] = []
    @Published var historyIndex: Int?

    @Published var selectedFeedOverride: Int = 100
    @Published var spindleRPM = "12000"

    /// Owns streaming individual lines to the machine (MDI, jogging, small
    /// macros) — see its doc comment for why this isn't used for whole jobs
    /// anymore now that `uploader` (Roadmap 1.2) exists.
    @Published var jobRunner = GCodeJobRunner()

    /// Owns uploading a whole loaded G-code program to the machine's SD
    /// card — see its doc comment for why real jobs go through here instead
    /// of `jobRunner` (Roadmap 1.2).
    @Published var uploader = GCodeUploader()

    @Published var isGCodeImporterPresented = false
    @Published var isShowingCommandPalette = false
    @Published var isLightOn = false
    @Published var terminalAutoScroll = true

    /// Canvas/render state, deliberately kept off `ControllerModel` itself —
    /// see `CanvasSceneModel`'s doc comment for why: mutating it on every
    /// scrub tick would otherwise re-render every panel that shares this
    /// `ControllerModel` instance.
    let scene = CanvasSceneModel()

    /// Speed of a held jog in mm/min (see `JogController`). Published so the
    /// jog panel's picker can bind to it.
    @Published var holdJogFeed: Double = 750 {
        didSet {
            jogController.holdFeed = holdJogFeed
        }
    }

    /// Owns everything that moves the machine by hand — step jogs and the
    /// timer behind hold-to-jog.
    lazy var jogController = JogController(
        send: { [weak self] line in
            self?.sendRawCommand(line, recordInHistory: false)
        },
        state: { [weak self] in
            self?.connection.status?.state
        },
        log: { [weak self] message in
            self?.connection.appendLog(message)
        }
    )

    init() {
        jobRunner.configure { [weak self] line in
            self?.sendRawCommand(line, recordInHistory: false)
        }
        uploader.configure(
            sendLine: { [weak self] line in
                self?.sendRawCommand(line, recordInHistory: false)
            },
            sendRawBytes: { [weak self] bytes, completion in
                self?.connection.sendRawBytes(bytes, completion: completion)
            },
            sendFrame: { [weak self] ptype, payload, completion in
                self?.connection.sendFileFrame(ptype: ptype, payload: payload, completion: completion)
            },
            wireProtocol: { [weak self] in
                self?.connection.wireProtocol
            }
        )
        // `upload` only writes the file — Smoothieware's own `play <path>`
        // console command is what actually starts the job running from it.
        uploader.onCompleted = { [weak self] remotePath in
            self?.sendRawCommand("play \(remotePath)", recordInHistory: false)
        }
        connection.onLine = { [weak self] line in
            self?.jobRunner.handleMachineLine(line)
            self?.uploader.handleMachineLine(line)
        }

        #if os(macOS)
        // A held button's release is never delivered once the app is in the
        // background, so switching away mid-jog must stop the jog itself.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.jogController.stopAll()
            }
        }
        #endif
    }

    func sendCommand(_ command: CNCCommand) {
        sendRawCommand(command.command)
    }

    func sendPaletteCommand(_ paletteCommand: PaletteCommand) {
        if let command = paletteCommand.command {
            sendCommand(command)
        } else {
            sendRawCommand(paletteCommand.rawCommand)
        }
    }

    /// `recordInHistory: false` keeps high-frequency, machine-generated lines
    /// (jog steps) from pushing the commands the user actually typed out of
    /// the 10-entry MDI history. They still show up in the terminal log.
    func sendRawCommand(_ command: String, recordInHistory: Bool = true) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !command.isEmpty else {
            return
        }

        guard connection.isConnected else {
            return
        }

        // "?", "!", "~" and "^X" are realtime control bytes, not queued
        // lines/frames — route them through the protocol-aware realtime
        // path so they work under both the plain-text and framed wire
        // protocols (typed into the MDI box or picked from the palette).
        if let realtime = realtimeCommand(for: command) {
            if realtime == .softReset {
                softReset()
            } else {
                connection.sendRealtime(realtime)
            }
            return
        }

        if recordInHistory {
            addToHistory(command)
        }
        connection.send(command)
    }

    // MARK: - Jogging

    /// A move requested from `PanelJog`. Kept as an explicit choice between
    /// relative and absolute because `G0` alone is always interpreted in
    /// whatever distance mode the machine happens to be in (G90 by default),
    /// so "move X by +0.1" and "go to X 0.1" can't share one command.
    enum JogRequest {
        /// Move each given axis by this distance from where it is now
        /// (mm for X/Y/Z, degrees for A).
        case relative(x: Double?, y: Double?, z: Double?, a: Double?)
        /// Move each given axis to this work coordinate.
        case absolute(x: Double?, y: Double?, z: Double?, a: Double?)
    }

    func jog(_ request: JogRequest) {
        switch request {
        case let .relative(x, y, z, a):
            jogController.step(x: x, y: y, z: z, a: a)
        case let .absolute(x, y, z, a):
            jogController.goTo(x: x, y: y, z: z, a: a)
        }
    }

    /// Hold-to-jog: moves in `direction` from `pressed == true` until
    /// `pressed == false`. See `JogController` for how, and its limits.
    func holdJog(_ direction: JogDirection, pressed: Bool) {
        if pressed {
            jogController.press(direction)
        } else {
            jogController.release(direction)
        }
    }

    func stopHoldJog() {
        jogController.stopAll()
    }

    // MARK: - Job execution

    /// Uploads `contents` to the machine's SD card as `fileName`, replacing
    /// the old line-by-line `startJob` for real jobs — see `GCodeUploader`'s
    /// doc comment for why. No-op while disconnected or while an upload is
    /// already in flight.
    func uploadJob(fileName: String, contents: String) {
        guard connection.isConnected else { return }
        uploader.upload(fileName: fileName, contents: Data(contents.utf8))
    }

    /// Cancels an in-flight upload only. `stopJob()` is the general "stop"
    /// (it calls this when an upload is what's active).
    func cancelUpload() {
        uploader.cancel()
    }

    /// Starts streaming `lines` one at a time. Still the right call for
    /// MDI-style manual sends; use `uploadJob` for a whole program.
    func startJob(lines: [String]) {
        guard connection.isConnected else { return }
        jobRunner.start(lines: lines)
    }

    // MARK: - Pause / resume / abort (Roadmap 1.3)
    //
    // These work on whatever the *machine* is doing, whether that's a
    // program running from the SD card after `GCodeUploader` finished, or a
    // burst streamed by `GCodeJobRunner` — the realtime bytes act on the
    // machine, not on either queue. Enablement is therefore driven by the
    // machine's reported state (`MakeraMachineStatus`), which also covers a
    // job that was started or paused from the machine's own controls.

    /// Feed-hold: decelerates to a stop, keeping the job resumable.
    func pauseJob() {
        guard connection.isConnected else { return }

        // Stop the streamed queue regardless of machine state.
        jobRunner.pause()

        // A feed-hold only means something while there's motion to hold.
        // Sent to an idle machine it could leave a stale hold pending for
        // whatever runs next, so it's gated on the machine's own report.
        guard connection.status?.isRunning == true else { return }
        connection.sendRealtime(.feedHold)
        connection.requestStatus()
    }

    /// Resumes whichever kind of pause the machine is in. They're resumed
    /// differently: a feed-hold (`Hold`) takes the realtime `~`, but a job
    /// paused by the console `suspend` command (`Pause` — e.g. started from
    /// the machine's own controls) only responds to the console `resume`
    /// command. Sending `~` to a suspended machine does nothing.
    func resumeJob() {
        guard connection.isConnected else { return }

        // Resume the machine first so it's already moving again by the
        // time the runner queues its next line.
        if let status = connection.status {
            if status.isSuspended {
                sendRawCommand(consoleResumeCommand, recordInHistory: false)
                connection.requestStatus()
            } else if status.isFeedHeld {
                connection.sendRealtime(.cycleResume)
                connection.requestStatus()
            }
        }
        jobRunner.resume()
    }

    /// Stops the job outright.
    /// - Mid-upload: cancels the transfer. Nothing is running on the machine
    ///   yet, so there's nothing to reset (and in plain-text mode
    ///   `GCodeUploader.cancel()` already sends its own Ctrl-X).
    /// - Otherwise: a soft-reset, if the machine (or the streamed queue)
    ///   actually has something in progress. Unlike a feed-hold this is not
    ///   resumable — see `softReset()`.
    func stopJob() {
        if uploader.isActive {
            cancelUpload()
            jobRunner.stop()
            return
        }

        guard connection.isConnected else {
            jobRunner.stop()
            return
        }

        // Read before `softReset()` clears the runner.
        let somethingToAbort = jobRunner.isActive || connection.status?.isBusy == true
        guard somethingToAbort else { return }
        softReset()
    }

    /// Ctrl-X. Halts motion immediately and discards the machine's planned
    /// moves, so unlike `pauseJob()` there is no resuming from where it
    /// stopped. Grbl/Smoothie-style firmware usually comes back in ALARM and
    /// needs an Unlock (`$X`) before it accepts motion again — deliberately
    /// left as a manual step rather than auto-unlocking after an abort.
    private func softReset() {
        // Order matters: empty the queue first so an "ok" that's still on
        // its way can't trigger another line after the reset.
        jobRunner.stop()
        jogController.stopAll()

        guard connection.sendRealtime(.softReset) else { return }
        connection.appendLog("Soft reset sent. If the machine reports ALARM, use Unlock to clear it.")
        connection.requestStatus()
    }

    // MARK: - Raw commands not modeled by CNCCommand

    /// Grbl/Smoothieware-style homing command. Confirmed against
    /// Carvera_Controller/carveracontroller/Controller.py -> home().
    let homeCommand = "$H"

    /// Grbl/Smoothieware-style alarm-clear/unlock command. Confirmed against
    /// Controller.py -> unlock().
    let unlockCommand = "$X"

    /// Realtime status query byte — handled specially in sendRawCommand(),
    /// since it needs the protocol-aware realtime path, not a queued line.
    let statusCommand = "?"

    /// Realtime feed-hold and cycle-resume bytes (Roadmap 1.3). Same
    /// treatment as `statusCommand`.
    let feedHoldCommand = "!"
    let resumeCommand = "~"

    /// Console (line) command that resumes a job paused by `suspend` — not
    /// to be confused with `resumeCommand` above, which is the realtime `~`
    /// that resumes a feed-hold. See `resumeJob()`.
    let consoleResumeCommand = "resume"

    /// Printable stand-in for Ctrl-X (0x18), which can't be shown in the
    /// palette or typed into the MDI box. Sends the soft-reset byte.
    let softResetCommand = "^X"

    private func realtimeCommand(for command: String) -> MachineRealtimeCommand? {
        switch command {
        case statusCommand: return .statusQuery
        case feedHoldCommand: return .feedHold
        case resumeCommand: return .cycleResume
        case softResetCommand: return .softReset
        default: return nil
        }
    }

    /// Builds a "set current axis position as zero" command. Matches the
    /// reference app's wcs_set(): G10 L20 P0 sets the active work coordinate
    /// system offset so the machine's *current* physical position reads as
    /// the given value (0) on the specified axes. (CNCCommand doesn't model
    /// this yet — G92 would only be a temporary offset, not equivalent.)
    func zeroCommand(x: Bool = false, y: Bool = false, z: Bool = false) -> String {
        var command = "G10L20P0"
        if x { command += "X0" }
        if y { command += "Y0" }
        if z { command += "Z0" }
        return command
    }

    // MARK: - Sending Commands

    func toggleLight() {
        let command = isLightOn ? CNC.lightOff : CNC.lightOn
        sendCommand(command)
        isLightOn.toggle()
    }

    func sendMDI() {
        let command = mdiInput
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !command.isEmpty else {
            return
        }

        sendRawCommand(command)

        mdiInput = ""
        historyIndex = nil
    }



    // MARK: - Command History

    func addToHistory(_ command: String) {
        if commandHistory.last == command {
            return
        }

        commandHistory.removeAll {
            $0 == command
        }

        commandHistory.append(command)

        if commandHistory.count > 10 {
            commandHistory.removeFirst(
                commandHistory.count - 10
            )
        }
    }

    func historyPrevious() {
        guard !commandHistory.isEmpty else {
            return
        }

        if let index = historyIndex {
            historyIndex = max(0, index - 1)
        } else {
            historyIndex = commandHistory.count - 1
        }

        if let index = historyIndex {
            mdiInput = commandHistory[index]
        }
    }

    func historyNext() {
        guard let index = historyIndex else {
            return
        }

        if index + 1 < commandHistory.count {
            historyIndex = index + 1
            mdiInput = commandHistory[index + 1]
        } else {
            historyIndex = nil
            mdiInput = ""
        }
    }

    // MARK: - Terminal

    func clearTerminal() {
        connection.clearLogs()
    }

    var favoriteCommands: [PaletteCommand] {
        [
            PaletteCommand(title: "Get status", rawCommand: statusCommand),
            PaletteCommand(title: "Spindle stop", command: CNC.spindleOff),
            PaletteCommand(title: "Home", rawCommand: homeCommand),
            PaletteCommand(title: "Set XYZ zero", rawCommand: zeroCommand(x: true, y: true, z: true)),
            PaletteCommand(title: "Light on", command: CNC.lightOn),
            PaletteCommand(title: "Light off", command: CNC.lightOff)
        ]
    }
}
