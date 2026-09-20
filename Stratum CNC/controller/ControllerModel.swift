//
//  AppModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import Combine
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
    /// Tool number for the ATC panel's M6 button (Roadmap 2.1). String, not
    /// Int, for the same reason as `spindleRPM` — it's a `TextField`
    /// binding, and `Int(_:)` on the way out handles the empty/partial-entry
    /// case rather than a formatter. Per `CNCCommand.toolChange`'s doc
    /// comment: T0 is the wireless probe, T-1 is "none".
    @Published var atcToolNumber = "1"
    /// Power percentages for the internal vacuum (M801 S<n>), spindle
    /// cooling fan (M811 S<n>) and extended port (M851 S<n>) — Roadmap 2.2.
    /// String-backed `TextField` bindings, same reasoning as `spindleRPM`;
    /// `PercentageBuilder.with(percent:)` clamps to 0...100 on the way out,
    /// so an out-of-range or unparseable entry can't reach the machine.
    @Published var vacuumPercent = "100"
    @Published var coolingFanPercent = "100"
    @Published var extendedPortPercent = "100"

    /// Owns streaming individual lines to the machine (MDI, jogging, small
    /// macros) — see its doc comment for why this isn't used for whole jobs
    /// anymore now that `uploader` (Roadmap 1.2) exists.
    @Published var jobRunner = GCodeJobRunner()

    /// Owns uploading a whole loaded G-code program to the machine's SD
    /// card — see its doc comment for why real jobs go through here instead
    /// of `jobRunner` (Roadmap 1.2).
    @Published var uploader = GCodeUploader()

    /// SD-card path of the most recently completed upload, set once by
    /// `uploader.onCompleted` below. `resumeJob(fromLine:)` (Roadmap 1.5)
    /// needs this: `goto <line>` repositions the file the firmware already
    /// has loaded, but doesn't itself say which file, so a resume-from-line
    /// only makes sense while this still points at what's on the SD card.
    /// Left stale (not re-verified) after a *different* local file is
    /// loaded/scrubbed without being re-uploaded — there's no way to ask the
    /// firmware what it currently has loaded, so this is a best-effort
    /// "last thing we sent it", same caveat as `lastJob` on the status side.
    ///
    /// Persisted, so "Resume from Line" still works after the app was closed
    /// while a job sat suspended on the machine — the suspended state itself
    /// lives on the machine, this is just the file name to seek in.
    @Published private(set) var lastUploadedRemotePath: String? = UserDefaults.standard.string(forKey: "lastUploadedRemotePath") {
        didSet { UserDefaults.standard.set(lastUploadedRemotePath, forKey: "lastUploadedRemotePath") }
    }

    /// The canvas XY offset (mm, measured from the canvas origin — the
    /// anchor's inside corner) that was on screen when the current upload
    /// was started. Captured then, not read when the upload finishes, so
    /// nudging the offset while the file is still transferring can't change
    /// where the job that was just sent ends up. Consumed by
    /// `applyJobOrigin()` right before `play`.
    private var pendingJobOffset: SIMD2<Float> = .zero

    // MARK: Alerts

    /// Tool changes, alarms, errors and lost connections, made hard to miss
    /// (`MachineAlerts.swift`). Observed by the view through `.machineAlerts`
    /// rather than published from here, like `connection`'s own state.
    let alerts = MachineAlertCenter()

    private var cancellables = Set<AnyCancellable>()

    /// The status state before the current one, without its `:sub-state`
    /// ("Hold:0" → "Hold"). Empty while disconnected, so the first report
    /// after connecting isn't mistaken for a transition.
    private var lastBaseState = ""

    /// The most recent alarm/error text, to say *what* went wrong when the
    /// status change is what announces it.
    private var lastFault: (text: String, date: Date)?

    /// When the app itself last sent `suspend`, so the resulting Pause state
    /// isn't reported as "paused by the machine". Cleared when it's used,
    /// and when the job ends without ever getting there.
    private var suspendRequestedAt: Date?

    // MARK: Auto level before run

    /// When on, "Send to Machine" probes a `G32` grid over the program's
    /// cutting area — after the origin is set and before `play`. Persisted,
    /// because it's a workflow choice, not a per-job one.
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
    /// `G32`'s H: the height the probe lifts to between points (the doc
    /// example for the command uses 2 mm).
    private let levelProbeHeight = 2.0

    /// The cutting area of the program being sent, captured with the offset
    /// in `uploadJob` for the same reason. `nil` when leveling is off.
    private var pendingLevelingArea: GCodeBounds?

    /// SD path of a job whose `play` is being held back until the pre-run
    /// leveling finishes. Non-nil means "a run is being prepared"; clearing
    /// it (Stop does) cancels the `play`.
    private var pendingPlayPath: String?

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
            guard let self else { return }
            self.lastUploadedRemotePath = remotePath
            self.startRun(remotePath: remotePath)
        }
        jobRunner.onFinish = { [weak self] in
            self?.levelingFinished()
        }
        connection.onLine = { [weak self] line in
            self?.jobRunner.handleMachineLine(line)
            self?.uploader.handleMachineLine(line)
            self?.raiseAlert(forLine: line)
        }
        connection.$status
            .map { $0?.state.split(separator: ":").first.map { String($0) } ?? "" }
            .removeDuplicates()
            .sink { [weak self] state in
                Task { @MainActor in self?.machineStateChanged(to: state) }
            }
            .store(in: &cancellables)
        connection.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                Task { @MainActor in self?.connectionChanged(connected) }
            }
            .store(in: &cancellables)

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
        guard connection.isConnected, !uploader.isActive, pendingPlayPath == nil else { return }

        var area: GCodeBounds?
        if levelBeforeRun {
            // Refuse rather than silently run unleveled: the toggle is an
            // explicit "don't cut without a height map".
            guard let bounds = GCodeBounds.cutting(in: contents) else {
                connection.appendLog("Auto level is on, but the program has no XY cutting moves to measure. Nothing was sent.")
                return
            }
            area = bounds
        }

        pendingJobOffset = scene.xyOffset
        pendingLevelingArea = area
        uploader.upload(fileName: fileName, contents: Data(contents.utf8))
    }

    // MARK: - Job origin (anchor positioning)

    /// The lines that put the job where the canvas shows it: millimeters,
    /// G54 selected, and G54's XY origin set to the job offset with
    /// `G10 L2 P1`. Z is deliberately left out so it keeps whatever the Z
    /// probe / Auto Z step established.
    ///
    /// The offset is used as-is, i.e. it's taken to be the machine XY
    /// position of the work origin — which is only true while the canvas
    /// origin (the anchor's inside corner) coincides with the machine's XY
    /// origin. If the anchor turns out to sit elsewhere in machine
    /// coordinates, this is the one place to add that base position (and any
    /// axis sign flip).
    func jobOriginCommands(for offset: SIMD2<Float>) -> [String] {
        [
            CNC.millimeterMode.command,
            CNC.workspaceG54.command,
            CNC.setWorkspaceCoordinates
                .with(workspace: 1, x: Double(offset.x), y: Double(offset.y))
                .command
        ]
    }

    // MARK: - Alerts

    /// Alarm, error and tool-change lines from the machine.
    private func raiseAlert(forLine line: String) {
        guard let alert = MachineAlertRules.alert(forLine: line) else { return }
        if alert.kind == .alarm || alert.kind == .error {
            lastFault = (alert.message, Date())
        }
        alerts.post(alert)
    }

    /// The status report is the second source of truth: it catches a stop
    /// the machine didn't explain in text, and tells us when the cause has
    /// gone away (someone resumed or unlocked at the machine itself).
    private func machineStateChanged(to state: String) {
        let previous = lastBaseState
        lastBaseState = state

        // First report after connecting, and a job is sitting suspended on
        // the machine: the "continue later" moment. Say where it stopped.
        if previous.isEmpty, state == "Pause" {
            var message = "A job is suspended on the machine."
            if let job = connection.status?.activeJob {
                message = "A job is suspended on the machine at line \(job.currentLine) (\(job.percent)%, \(job.elapsedText) elapsed)."
            }
            alerts.post(MachineAlert(
                kind: .suspendedJob,
                title: "Suspended job",
                message: message + " If it stopped for a tool change, do that first, then resume."
            ))
            return
        }

        guard !state.isEmpty, !previous.isEmpty, state != previous else { return }

        // The job ended (or the machine faulted) before a requested suspend
        // took effect: a later pause is then not ours.
        if state == "Idle" || state == "Alarm" { suspendRequestedAt = nil }

        switch state {
            case "Alarm":
                // The explaining line normally arrives first and has already
                // raised its own alert.
                if !alerts.wasPosted(.alarm, within: 10) {
                    var detail = "The machine stopped with an alarm. Check the terminal, then Unlock to clear it."
                    if let fault = lastFault, Date().timeIntervalSince(fault.date) < 15 {
                        detail = fault.text
                    }
                    alerts.post(MachineAlert(kind: .alarm, title: "Machine alarm", message: detail))
                }
            case "Pause":
                if let requested = suspendRequestedAt, Date().timeIntervalSince(requested) < 60 {
                    // Our own `suspend` took effect — the person knows.
                    suspendRequestedAt = nil
                } else if !alerts.wasPosted(.toolChange, within: 60) {
                    // Otherwise the machine paused itself — usually to wait
                    // for a tool change. Skipped when a specific tool-change
                    // prompt already said so.
                    alerts.post(MachineAlert(
                        kind: .paused,
                        title: "Job paused by the machine",
                        message: "It may be waiting for a tool change. Check the machine, then resume."
                    ))
                }
            default:
                break
        }

        if previous == "Pause" { alerts.resolve([.toolChange, .paused, .suspendedJob]) }
        if previous == "Alarm" { alerts.resolve([.alarm]) }
    }

    private func connectionChanged(_ connected: Bool) {
        if connected {
            alerts.requestAuthorization()
            return
        }
        // `lastError` is only set by failures, not by an ordinary disconnect.
        if connection.lastError != nil, ["Run", "Hold", "Pause"].contains(lastBaseState) {
            alerts.post(MachineAlert(
                kind: .connectionLost,
                title: "Lost connection to the machine",
                message: "A job that was already started from the SD card should keep running on the machine. Reconnect to monitor it."
            ))
        }
        lastBaseState = ""
    }

    // MARK: - Run sequence (origin → auto level → play)

    /// Runs once the file is on the SD card. Without leveling it's the
    /// original two steps: set the origin, then `play`. With leveling the
    /// origin lines, `M370` and `G32` go through `jobRunner`, because each
    /// must be acknowledged before the next (the probe cycle has to be over
    /// before anything else moves), and `play` follows in `levelingFinished`.
    private func startRun(remotePath: String) {
        guard let area = pendingLevelingArea else {
            applyJobOrigin()
            sendRawCommand("play \(remotePath)", recordInHistory: false)
            return
        }

        // Starting the job anyway would mean cutting unleveled, so an
        // already-running macro (Auto Z, say) cancels the run, not the level.
        guard !jobRunner.isActive else {
            connection.appendLog("Auto level: another command sequence is running, so the job was uploaded but not started.")
            return
        }

        let margin = levelMargin
        let points = Double(levelGridPoints)
        let probe = CNC.probeGrid.with(
            r: 1,
            x: area.minX - margin, y: area.minY - margin,
            a: area.width + 2 * margin, b: area.height + 2 * margin,
            i: points, j: points,
            h: levelProbeHeight
        ).command

        // M370 first so a probe that fails halfway can't leave the previous
        // job's grid active.
        let lines = jobOriginCommands(for: pendingJobOffset) + [CNC.clearBedLeveling.command, probe]

        pendingPlayPath = remotePath
        connection.appendLog("Auto level before run: \(probe)")
        jobRunner.start(lines: lines)
    }

    /// The pre-run lines have all been acknowledged. Also fires for any other
    /// `jobRunner` macro finishing, hence the `pendingPlayPath` check.
    private func levelingFinished() {
        guard let path = pendingPlayPath else { return }
        Task { await self.playWhenIdle(path) }
    }

    /// Starts `play` only once the machine itself reports Idle, not merely
    /// once `G32` was acknowledged: that the probe's "ok" waits for the whole
    /// cycle is assumed (see `autoZeroProbe`), not confirmed for this
    /// firmware, and starting a program in the middle of probing would be
    /// bad. Bails out on Alarm, Stop, disconnect, or after ten minutes.
    private func playWhenIdle(_ path: String) async {
        let deadline = Date().addingTimeInterval(600)

        // Let a status report that predates the last line clear out.
        connection.requestStatus()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        while pendingPlayPath == path {
            let state = connection.status?.state ?? ""

            if !connection.isConnected || state.hasPrefix("Alarm") || Date() > deadline {
                connection.appendLog("Auto level did not finish cleanly (\(state.isEmpty ? "no status" : state)); the job was not started.")
                pendingPlayPath = nil
                return
            }
            if state.hasPrefix("Idle") { break }

            connection.requestStatus()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Stop (or a newer run) cleared/replaced it while waiting.
        guard pendingPlayPath == path else { return }
        pendingPlayPath = nil
        sendRawCommand("play \(path)", recordInHistory: false)
    }

    /// Sends `jobOriginCommands` for the offset captured by `uploadJob`.
    /// These are non-motion, order-preserving lines, so they don't need the
    /// `jobRunner` ack sequencing `autoZeroProbe()` does — the machine
    /// handles them in the order they arrive, before `play`.
    private func applyJobOrigin() {
        let offset = pendingJobOffset
        connection.appendLog("Setting G54 work origin to X\(offset.x) Y\(offset.y) (job offset).")
        for line in jobOriginCommands(for: offset) {
            sendRawCommand(line, recordInHistory: false)
        }
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

    /// Suspends the running job so it can be picked up later, unlike
    /// `pauseJob()`'s feed-hold, which is a momentary stop. Per the firmware
    /// (see `MakeraMachineStatus.isSuspended`) `suspend` lets the planner
    /// drain, saves the position and stops the spindle — so the machine is
    /// safe to leave, and to jog or MDI around while it waits. Continue with
    /// `resumeJob()` (console `resume`), also after the app was closed and
    /// reopened: the suspended state lives on the machine, not here.
    ///
    /// Only offered for a job playing from the SD card and currently moving.
    /// A macro streamed by `jobRunner` (the auto-level pre-run, Auto Z) has
    /// nothing the firmware could suspend.
    func suspendJob() {
        guard connection.isConnected,
              let status = connection.status,
              status.isRunning,
              status.activeJob != nil else { return }

        suspendRequestedAt = Date()
        sendRawCommand(consoleSuspendCommand, recordInHistory: false)
        connection.requestStatus()
    }

    /// Resumes whichever kind of pause the machine is in, from wherever it
    /// actually paused. See `resumeJob(fromLine:)` to resume from a chosen
    /// line instead (Roadmap 1.5).
    func resumeJob() {
        resumeJob(fromLine: nil)
    }

    /// Resumes a held job the same way `resumeJob()` does, but first
    /// repositions the SD-card file's read pointer with the console
    /// `goto <line>` command (Roadmap 1.5) — so the job can restart earlier
    /// or later than wherever the hold actually happened, e.g. to redo a
    /// cut that came out wrong or skip past a broken tool change. Passing
    /// `nil` is exactly `resumeJob()`.
    ///
    /// `goto` only seeks; it isn't a play command by itself, so it's sent
    /// *before*, never instead of, the same feed-hold/`suspend` resume
    /// below — matches Player.cpp's other file-position console commands
    /// (`play <path>`, `progress`), which are all separate from the
    /// realtime `~`/console `resume` that actually restarts motion. Only
    /// meaningful for a job that came from `uploader` (an SD-card file, not
    /// `jobRunner`'s streamed queue, which has no file to seek in), so
    /// `line` is silently ignored unless `lastUploadedRemotePath` is set.
    ///
    /// Not confirmed against real hardware or against Player.cpp's console
    /// command source directly (wasn't accessible while writing this) —
    /// this follows the roadmap's own `goto <line>` phrasing and the shape
    /// of Player.cpp's other console commands, but it's worth checking
    /// against a real machine, or ideally the firmware source, before
    /// relying on it for anything valuable. If `goto` turns out to need the
    /// path repeated (e.g. `goto <path> <line>`) rather than a bare line
    /// number, this is the one place to fix it.
    func resumeJob(fromLine line: Int?) {
        guard connection.isConnected else { return }

        if let line, lastUploadedRemotePath != nil {
            sendRawCommand("goto \(line)", recordInHistory: false)
        }

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
        pendingPlayPath = nil   // cancels a `play` still waiting on leveling
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
        pendingPlayPath = nil
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

    /// Console (line) command that suspends a job at the next safe point.
    /// The counterpart of `consoleResumeCommand`; see `suspendJob()`.
    let consoleSuspendCommand = "suspend"

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

    /// Probes down at the current XY, then zeroes the work Z coordinate at
    /// the trigger point (Roadmap 4.1). A plain "Probe Z" (see `PanelProbe`)
    /// only does the first half, which is what this used to be wired to as
    /// well — a copy-paste bug, not a deliberate duplicate. Makera's own
    /// wiki describes "Auto Z Probe" as exactly this combined action: "Z-axis
    /// tool setting is required after changing the workpiece or the zero
    /// points of the work coordinate" (wiki.makera.com/en/carvera/manual/software).
    ///
    /// The two lines have to be sequenced, not fired together — the zero
    /// has to land *after* the tool has actually stopped at the trigger
    /// point, not wherever it started. Routed through `jobRunner` (a
    /// 2-line "macro", exactly what it's documented for) rather than two
    /// back-to-back `sendCommand` calls, since `jobRunner` only advances on
    /// the machine's "ok" for the *previous* line. That in turn assumes the
    /// probe's "ok" is withheld until the probe cycle itself finishes
    /// (documented grbl/Smoothieware-family behavior — unlike an ordinary
    /// buffered move, the trigger position isn't known, and so the line
    /// isn't acked, until the probe actually stops) — not confirmed against
    /// Carvera's firmware specifically, so worth checking against a real
    /// machine before trusting it blindly.
    ///
    /// Zeroes with a flat `Z0` at the trigger point (`zeroCommand`, `G10
    /// L20 P0 Z0`) — there's no probe-plate-thickness setting modeled in
    /// this app yet to offset by, unlike the community "touch plate off"
    /// macros this pattern is otherwise borrowed from. Correct for probing
    /// straight onto the stock/table surface; wrong if probing against a
    /// plate of known thickness instead.
    func autoZeroProbe() {
        guard connection.isConnected, !jobRunner.isActive else { return }
        jobRunner.start(lines: [
            CNC.probe.with(z: -10, feed: 50).command,
            zeroCommand(z: true)
        ])
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
