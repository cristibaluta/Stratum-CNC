//
//  AppModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import Combine
import simd
import StratumLink
#if os(macOS)
import AppKit
#endif

/// The app-side model of the controller screen. The machine logic itself —
/// connecting, uploading, origin/leveling/play sequencing, pause/suspend/
/// resume/stop, and spotting alarms and tool changes — lives in
/// `SL.Session`. This class only adds what belongs to the app: UserDefaults
/// persistence, the canvas offset, the alert presentation, the MDI box and
/// its history, jogging, and panel state.
@MainActor
class ControllerModel: ObservableObject {

    @Published var discovery = SL.Discovery()
    @Published var selectedMachine: SL.MakeraMachine?

    /// The machine logic. Views reach its parts through the forwarding
    /// properties below.
    let session: SL.Session

    var connection: SL.Connection { session.connection }

    /// Owns streaming individual lines to the machine (MDI, jogging, small
    /// macros) — see its doc comment for why this isn't used for whole jobs.
    var jobRunner: SL.JobRunner { session.jobRunner }

    /// Owns uploading a whole loaded G-code program to the machine's SD card.
    var uploader: SL.Uploader { session.uploader }

    @Published var mdiInput = ""
    @Published var commandHistory: [String] = []
    @Published var historyIndex: Int?

    @Published var selectedFeedOverride: Int = 100
    @Published var spindleRPM = "12000"
    /// Tool number for the ATC panel's M6 button. String because it's a
    /// `TextField` binding. T0 is the wireless probe, T-1 is "none".
    @Published var atcToolNumber = "1"
    /// Power percentages for the internal vacuum (M801), spindle cooling fan
    /// (M811) and extended port (M851). String-backed `TextField` bindings;
    /// the command builders clamp to 0...100.
    @Published var vacuumPercent = "100"
    @Published var coolingFanPercent = "100"
    @Published var extendedPortPercent = "100"

    /// SD-card path of the most recently completed upload. Mirrors
    /// `session.lastUploadedRemotePath` (so views refresh) and persists it, so
    /// "Resume from Line" still works after the app was closed while a job
    /// sat suspended on the machine.
    @Published private(set) var lastUploadedRemotePath: String? {
        didSet { UserDefaults.standard.set(lastUploadedRemotePath, forKey: "lastUploadedRemotePath") }
    }

    // MARK: Alerts

    /// Tool changes, alarms, errors and lost connections, made hard to miss
    /// (`MachineAlert.swift`). Observed by the view through `.machineAlerts`.
    let alerts = MachineAlertCenter()

    // MARK: Auto level before run

    /// When on, "Send to Machine" probes a `G32` grid over the program's
    /// cutting area before `play`. Persisted: a workflow choice.
    @Published var levelBeforeRun: Bool = UserDefaults.standard.bool(forKey: "levelBeforeRun") {
        didSet { UserDefaults.standard.set(levelBeforeRun, forKey: "levelBeforeRun") }
    }
    /// Probe points per axis (`G32` I and J).
    @Published var levelGridPoints: Int = UserDefaults.standard.object(forKey: "levelGridPoints") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(levelGridPoints, forKey: "levelGridPoints") }
    }
    /// Extra area probed around the program's cutting bounds, in mm.
    @Published var levelMargin: Double = UserDefaults.standard.object(forKey: "levelMargin") as? Double ?? 3 {
        didSet { UserDefaults.standard.set(levelMargin, forKey: "levelMargin") }
    }

    /// When on, the pre-run macro also probes Z and zeroes the work Z
    /// coordinate before `play`. Persisted like `levelBeforeRun`.
    @Published var autoZBeforeRun: Bool = UserDefaults.standard.bool(forKey: "autoZBeforeRun") {
        didSet { UserDefaults.standard.set(autoZBeforeRun, forKey: "autoZBeforeRun") }
    }

    /// Mirrors the M331/M332 "tie vacuum to spindle" mode. Only ever what the
    /// app itself last commanded — the machine doesn't report it back.
    @Published var autoVacuumEnabled: Bool = false

    /// Presented when Play/"Send to Machine" is tapped with nothing
    /// connected, so the person can pick a machine first.
    @Published var isShowingMachinePicker = false

    /// Drives `MachiningRunSheet`, the pre-run review.
    @Published var isShowingRunReview = false

    @Published var isGCodeImporterPresented = false
    @Published var isShowingCommandPalette = false
    @Published var isLightOn = false
    @Published var terminalAutoScroll = true

    /// Canvas/render state, deliberately kept off `ControllerModel` itself —
    /// see `CanvasSceneModel`'s doc comment.
    let scene = CanvasSceneModel()

    /// Speed of a held jog in mm/min (see `JogController`).
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
        let savedPath = UserDefaults.standard.string(forKey: "lastUploadedRemotePath")
        session = SL.Session(lastUploadedRemotePath: savedPath)
        lastUploadedRemotePath = savedPath

        session.onLastUploadedRemotePathChange = { [weak self] path in
            self?.lastUploadedRemotePath = path
        }
        session.onEvent = { [weak self] event in
            self?.handle(event)
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

    /// Turns what the session reports into app behavior.
    private func handle(_ event: SL.SessionEvent) {
        switch event {
        case .alert(let alert):
            alerts.post(alert)
        case .alertsResolved(let kinds):
            alerts.resolve(kinds)
        case .connected:
            alerts.requestAuthorization()
        case .disconnected, .motionAborting:
            jogController.stopAll()
        }
    }

    func sendCommand(_ command: SL.Command) {
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

        guard !command.isEmpty, connection.isConnected else {
            return
        }

        // Realtime bytes ("?", "!", "~", "^X") aren't typed commands worth
        // recalling from the history.
        if recordInHistory, !session.isRealtimeCommand(command) {
            addToHistory(command)
        }
        session.sendRawCommand(command)
    }

    // MARK: - Jogging

    /// A move requested from `PanelJog`. Kept as an explicit choice between
    /// relative and absolute because `G0` alone is always interpreted in
    /// whatever distance mode the machine happens to be in.
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

    // MARK: - Job execution (see `SL.Session`)

    /// Uploads `contents` to the machine's SD card as `fileName` and runs it.
    /// The canvas offset and the pre-run settings are captured now, so
    /// changing them while the file is still transferring can't change where
    /// the job that was just sent ends up.
    func uploadJob(fileName: String, contents: String) {
        let options = SL.RunOptions(
            originOffset: scene.xyOffset,
            levelBeforeRun: levelBeforeRun,
            levelGridPoints: levelGridPoints,
            levelMargin: levelMargin,
            autoZBeforeRun: autoZBeforeRun
        )
        session.uploadJob(fileName: fileName, contents: contents, options: options)
    }

    /// The lines that put the job where the canvas shows it.
    func jobOriginCommands(for offset: SIMD2<Float>) -> [String] {
        SL.Session.jobOriginCommands(for: offset)
    }

    func cancelUpload() {
        session.cancelUpload()
    }

    /// Starts streaming `lines` one at a time. Still the right call for
    /// MDI-style manual sends; use `uploadJob` for a whole program.
    func startJob(lines: [String]) {
        session.startJob(lines: lines)
    }

    func pauseJob() {
        session.pauseJob()
    }

    func suspendJob() {
        session.suspendJob()
    }

    func resumeJob() {
        session.resumeJob()
    }

    func resumeJob(fromLine line: Int?) {
        session.resumeJob(fromLine: line)
    }

    func stopJob() {
        session.stopJob()
    }

    func autoZeroProbe() {
        session.autoZeroProbe()
    }

    // MARK: - Raw commands not modeled by CNCCommand

    let homeCommand = SL.Session.homeCommand
    let unlockCommand = SL.Session.unlockCommand
    let statusCommand = SL.Session.statusCommand
    let feedHoldCommand = SL.Session.feedHoldCommand
    let resumeCommand = SL.Session.resumeCommand
    let consoleResumeCommand = SL.Session.consoleResumeCommand
    let consoleSuspendCommand = SL.Session.consoleSuspendCommand
    let softResetCommand = SL.Session.softResetCommand

    func zeroCommand(x: Bool = false, y: Bool = false, z: Bool = false) -> String {
        SL.Session.zeroCommand(x: x, y: y, z: z)
    }

    // MARK: - Sending Commands

    func toggleLight() {
        let command = isLightOn ? CNC.lightOff : CNC.lightOn
        sendCommand(command)
        isLightOn.toggle()
    }

    /// M331/M332 — ties the vacuum to the spindle's on/off state. Used by
    /// both `PanelAccessories`' manual buttons and `MachiningRunSheet`'s
    /// "Assist Options" toggle; kept here so the two stay in sync.
    func setAutoVacuum(_ enabled: Bool) {
        sendCommand(enabled ? CNC.automaticVacuumOn : CNC.automaticVacuumOff)
        autoVacuumEnabled = enabled
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
