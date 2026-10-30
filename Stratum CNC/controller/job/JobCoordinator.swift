//
//  JobCoordinator.swift
//  Stratum CNC
//
//  Owns the job policy: what to send, and when, to upload, start, pause,
//  resume and stop a program on the machine. `SL.Session` is used only as a
//  transport (connection, uploader, small line macros).
//
//  The machine's firmware runs the program itself from its SD card
//  (`play <path>`), so this does not stream whole jobs line by line.
//

import Foundation
import Combine
import simd
import StratumLink

/// Per-run settings, captured when the run starts so that changing a setting
/// while a file is still transferring can't change the job that was sent.
struct JobRunOptions: Equatable {

    /// XY position (mm) the job's G54 work origin is set to right before `play`.
    var originOffset: SIMD2<Float> = .zero

    /// Probe a `G32` grid over the program's cutting area before `play`.
    var levelBeforeRun = false
    /// Probe points per axis (`G32` I and J).
    var levelGridPoints = 5
    /// Extra area probed around the program's cutting bounds, in mm.
    var levelMargin = 3.0

    /// Probe Z and zero the work Z coordinate at the trigger point before `play`.
    var autoZBeforeRun = false
}

@MainActor
final class JobCoordinator: ObservableObject {

    private let session: SL.Session
    private var connection: SL.Connection { session.connection }
    private var uploader: SL.Uploader { session.uploader }
    private var jobRunner: SL.JobRunner { session.jobRunner }

    private static let lastPathKey = "lastUploadedRemotePath"

    /// SD-card path of the most recently completed upload. `goto <line>` acts
    /// on the file the firmware has loaded, so a resume-from-line is only
    /// offered while this is known. Persisted so it survives an app restart
    /// while a job sits suspended on the machine.
    @Published private(set) var lastUploadedRemotePath: String? {
        didSet { UserDefaults.standard.set(lastUploadedRemotePath, forKey: Self.lastPathKey) }
    }

    /// What the app remembers about the job it started: the last line the
    /// machine reported, the file fingerprint, where the origin was set.
    /// Survives an app restart. Nil when there's nothing to resume.
    @Published private(set) var progress: JobProgress?

    private let store: JobProgressStore
    private var lastSavedAt = Date.distantPast
    /// Disk writes while only the line advances are spaced out; a phase
    /// change is always written at once.
    private static let saveInterval: TimeInterval = 2

    /// True from the moment a suspend is requested until the machine confirms
    /// it (or it fails). For disabling the button meanwhile.
    @Published private(set) var isSuspending = false
    private var suspendTask: Task<Void, Never>?
    private static let suspendTimeout: TimeInterval = 60

    /// UserDefaults key (`Bool`, off by default): after a suspend, also move to
    /// the machine's clearance position (`G28`). Read when the suspend finishes,
    /// so the Settings window can flip it without a reference to this object.
    static let parkAfterSuspendKey = "job.parkAfterSuspend"

    /// True while the pre-run steps (origin, probe, leveling, waiting for the
    /// machine to be idle) are in progress, before `play` has been sent.
    @Published private(set) var isPreparing = false

    /// The program last uploaded in this app session, kept to measure the
    /// leveling area and to fingerprint the job when the run is started later.
    private var lastUploadedContents: String?
    private var lastUploadedFileName: String?
    private var pendingContents: String?
    private var pendingFileName: String?

    /// Set when the upload should be followed by a run (`uploadAndRun`).
    private var runAfterUpload: JobRunOptions?

    /// Identifies the current run so a cancelled run's waiter can't start a
    /// replacement job that happens to have the same file name.
    private var pendingPlayID = UUID()
    /// SD path of a job whose `play` is being held back until the pre-run
    /// steps finish. Non-nil means "a run is being prepared"; clearing it
    /// (Stop does) cancels the `play`.
    private var pendingPlayPath: String? {
        didSet {
            pendingPlayID = UUID()
            isPreparing = pendingPlayPath != nil
        }
    }

    /// `G32`'s H: the height the probe lifts to between points.
    private let levelProbeHeight = 2.0

    private var cancellables = Set<AnyCancellable>()

    init(session: SL.Session, store: JobProgressStore = JobProgressStore()) {
        self.session = session
        self.store = store
        lastUploadedRemotePath = UserDefaults.standard.string(forKey: Self.lastPathKey)

        // A run that was only requested never reached the machine's player.
        if let saved = store.load(), saved.phase != .starting {
            progress = saved
        } else {
            store.clear()
        }

        // Take over the hooks the session wires for its own run sequence.
        uploader.onCompleted = { [weak self] path in
            self?.uploadCompleted(remotePath: path)
        }
        jobRunner.onFinish = { [weak self] in
            self?.preRunFinished()
        }
        jobRunner.onFailure = { [weak self] in
            self?.pendingPlayPath = nil
            self?.abandonStartingProgress()
        }

        connection.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                if !connected {
                    self?.runAfterUpload = nil
                    self?.pendingPlayPath = nil
                    self?.abandonStartingProgress()
                }
            }
            .store(in: &cancellables)

        connection.$status
            .sink { [weak self] status in
                self?.observe(status)
            }
            .store(in: &cancellables)
    }

    // MARK: - Progress

    /// Forgets the saved job, e.g. when the person decides not to resume it.
    func discardProgress() {
        progress = nil
        store.clear()
    }

    private func beginProgress(remotePath: String, options: JobRunOptions) {
        let contents = lastUploadedContents
        let fingerprint = contents.flatMap { text in
            lastUploadedFileName.map { ControllerModel.fingerprint(fileName: $0, contents: text) }
        }
        let totalLines = contents.map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0
        let record = JobProgress(
            fileName: lastUploadedFileName ?? (remotePath as NSString).lastPathComponent,
            fingerprint: fingerprint,
            remotePath: remotePath,
            originX: options.originOffset.x,
            originY: options.originOffset.y,
            totalLines: totalLines
        )
        progress = record
        persist(record)
    }

    private func markPlaySent() {
        guard var record = progress, record.phase == .starting else { return }
        record.markPlaySent()
        progress = record
        persist(record)
    }

    /// A run that was prepared but never reached `play`.
    private func abandonStartingProgress() {
        guard progress?.phase == .starting else { return }
        discardProgress()
    }

    private func persist(_ record: JobProgress) {
        lastSavedAt = Date()
        store.save(record)
    }

    private func observe(_ status: MakeraMachineStatus?) {
        guard var record = progress, let status else { return }

        let outcome = record.observe(
            machineState: status.state,
            active: status.activeJob.map { .init(line: $0.currentLine, percent: $0.percent) },
            frozen: status.lastJob.map { .init(line: $0.currentLine, percent: $0.percent) }
        )

        switch outcome {
        case .unchanged:
            break
        case .changed:
            let phaseChanged = record.phase != progress?.phase
            progress = record
            if phaseChanged || Date().timeIntervalSince(lastSavedAt) >= Self.saveInterval {
                persist(record)
            }
        case .completed, .discarded:
            discardProgress()
        }
    }

    // MARK: - Upload and run

    /// Uploads `contents` to the SD card without starting it.
    func upload(fileName: String, contents: String) {
        guard connection.isConnected, !uploader.isActive, pendingPlayPath == nil else { return }
        runAfterUpload = nil
        pendingContents = contents
        pendingFileName = fileName
        uploader.upload(fileName: fileName, contents: Data(contents.utf8))
    }

    /// Uploads `contents`, then runs it (origin → optional Z probe / leveling → `play`).
    func uploadAndRun(fileName: String, contents: String, options: JobRunOptions) {
        guard connection.isConnected, !uploader.isActive, pendingPlayPath == nil else { return }
        guard levelingArea(for: contents, options: options) != nil || !options.levelBeforeRun else {
            logNoLevelingArea()
            return
        }
        runAfterUpload = options
        pendingContents = contents
        pendingFileName = fileName
        uploader.upload(fileName: fileName, contents: Data(contents.utf8))
    }

    /// Runs the file `upload` last put on the machine.
    func runUploaded(options: JobRunOptions) {
        guard connection.isConnected, !uploader.isActive, pendingPlayPath == nil,
              let path = lastUploadedRemotePath else { return }
        let area = levelingArea(for: lastUploadedContents ?? "", options: options)
        if options.levelBeforeRun, area == nil {
            logNoLevelingArea()
            return
        }
        startRun(remotePath: path, options: options, area: area)
    }

    func cancelUpload() {
        runAfterUpload = nil
        uploader.cancel()
    }

    /// Starts streaming `lines` one at a time. For MDI-style manual sends and
    /// small macros, not for whole programs.
    func startLines(_ lines: [String]) {
        guard connection.isConnected else { return }
        jobRunner.start(lines: lines)
    }

    private func uploadCompleted(remotePath: String) {
        lastUploadedRemotePath = remotePath
        lastUploadedContents = pendingContents
        lastUploadedFileName = pendingFileName
        pendingContents = nil
        pendingFileName = nil

        guard let options = runAfterUpload else { return }
        runAfterUpload = nil
        let area = levelingArea(for: lastUploadedContents ?? "", options: options)
        startRun(remotePath: remotePath, options: options, area: area)
    }

    private func levelingArea(for contents: String, options: JobRunOptions) -> SL.Bounds? {
        options.levelBeforeRun ? SL.Bounds.cutting(in: contents) : nil
    }

    private func logNoLevelingArea() {
        // Refuse rather than silently run unleveled: the option is an
        // explicit "don't cut without a height map".
        connection.appendLog("Auto level is on, but the program has no XY cutting moves to measure. Nothing was started.")
    }

    /// With neither pre-run step on: set the origin, then `play`. Otherwise the
    /// origin lines plus the enabled probe steps go through `jobRunner`
    /// (each must be acknowledged before the next), and `play` follows in
    /// `preRunFinished` once the machine reports Idle again.
    private func startRun(remotePath: String, options: JobRunOptions, area: SL.Bounds?) {
        let offset = options.originOffset
        beginProgress(remotePath: remotePath, options: options)

        guard options.autoZBeforeRun || area != nil else {
            connection.appendLog("Setting G54 work origin to X\(offset.x) Y\(offset.y) (job offset).")
            for line in SL.Session.jobOriginCommands(for: offset) {
                session.sendRawCommand(line)
            }
            session.sendRawCommand("play \(remotePath)")
            markPlaySent()
            return
        }

        guard !jobRunner.isActive else {
            connection.appendLog("Auto Z/Level: another command sequence is running, so the job was not started.")
            abandonStartingProgress()
            return
        }

        var lines = SL.Session.jobOriginCommands(for: offset)
        var logMessages = ["Setting G54 work origin to X\(offset.x) Y\(offset.y) (job offset)."]

        if options.autoZBeforeRun {
            lines += [CNC.probe.with(z: -10, feed: 50).command, SL.Session.zeroCommand(z: true)]
            logMessages.append("Auto Z before run: probing and zeroing work Z.")
        }

        if let area {
            let margin = options.levelMargin
            let points = Double(options.levelGridPoints)
            let probe = CNC.probeGrid.with(
                r: 1,
                x: area.minX - margin, y: area.minY - margin,
                a: area.width + 2 * margin, b: area.height + 2 * margin,
                i: points, j: points,
                h: levelProbeHeight
            ).command
            // M370 first so a probe that fails halfway can't leave the
            // previous job's grid active.
            lines += [CNC.clearBedLeveling.command, probe]
            logMessages.append("Auto level before run: \(probe)")
        }

        pendingPlayPath = remotePath
        logMessages.forEach { connection.appendLog($0) }
        jobRunner.start(lines: lines)
    }

    /// The pre-run lines have all been acknowledged. Also fires for any other
    /// `jobRunner` macro finishing, hence the `pendingPlayPath` check.
    private func preRunFinished() {
        guard let path = pendingPlayPath else { return }
        let runID = pendingPlayID
        Task { await self.playWhenIdle(path, runID: runID) }
    }

    /// Starts `play` only once the machine itself reports Idle, not merely
    /// once `G32` was acknowledged. Bails out on Alarm, disconnect, or after
    /// ten minutes.
    private func playWhenIdle(_ path: String, runID: UUID) async {
        guard pendingPlayID == runID else { return }
        let deadline = Date().addingTimeInterval(600)

        // Let a status report that predates the last line clear out.
        connection.requestStatus()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        while pendingPlayID == runID && pendingPlayPath == path {
            let state = connection.status?.state ?? ""

            if !connection.isConnected || state.hasPrefix("Alarm") || Date() > deadline {
                connection.appendLog("Pre-run steps did not finish cleanly (\(state.isEmpty ? "no status" : state)); the job was not started.")
                pendingPlayPath = nil
                abandonStartingProgress()
                return
            }
            if state.hasPrefix("Idle") { break }

            connection.requestStatus()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Stop (or a newer run) cleared/replaced it while waiting.
        guard pendingPlayID == runID, pendingPlayPath == path else { return }
        pendingPlayPath = nil
        session.sendRawCommand("play \(path)")
        markPlaySent()
    }

    // MARK: - Pause / suspend / resume / stop

    /// Feed hold: decelerates to a stop, keeping the job resumable.
    func pause() {
        guard connection.isConnected else { return }

        // Stop the streamed queue regardless of machine state.
        jobRunner.pause()

        // A feed hold only means something while there's motion to hold.
        guard connection.status?.isRunning == true else { return }
        _ = connection.sendRealtime(.feedHold)
        connection.requestStatus()
    }

    /// Suspends the running job so it can be picked up later. The machine's own
    /// `suspend` does the hard part (lets the planner drain, saves the position,
    /// stops the spindle); the app owns what surrounds it: it waits until the
    /// machine really reports the suspended (Pause) state, makes sure the
    /// position is recorded in `progress`, and, if the person chose so, parks
    /// the head at the machine's clearance position so the work area is free.
    ///
    /// The request itself still goes through the session: it remembers that the
    /// suspend was ours, so the resulting Pause state isn't reported as "paused
    /// by the machine". That goes away once the alert policy moves into the app.
    func suspend() {
        guard connection.isConnected, !isSuspending,
              let status = connection.status, status.isRunning, status.activeJob != nil else { return }

        isSuspending = true
        session.suspendJob()
        suspendTask = Task { await self.finishSuspend() }
    }

    /// Waits for the machine to confirm the suspend. Gives up on Idle or Alarm
    /// (the job ended or faulted first), on disconnect, and after `suspendTimeout`.
    private func finishSuspend() async {
        defer {
            isSuspending = false
            suspendTask = nil
        }
        let deadline = Date().addingTimeInterval(Self.suspendTimeout)

        while !Task.isCancelled {
            guard connection.isConnected else { return }
            let state = connection.status?.state ?? ""

            if state.hasPrefix("Pause") { break }
            if state.hasPrefix("Idle") || state.hasPrefix("Alarm") {
                connection.appendLog("Suspend did not take effect: the machine is \(state).")
                return
            }
            if Date() > deadline {
                connection.appendLog("Suspend was not confirmed by the machine within \(Int(Self.suspendTimeout)) s.")
                return
            }
            connection.requestStatus()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !Task.isCancelled else { return }

        // The status that reported Pause has already updated `progress`; make
        // sure what the machine says is on disk before anything else happens.
        if let record = progress, record.phase == .suspended {
            persist(record)
        }

        if UserDefaults.standard.bool(forKey: Self.parkAfterSuspendKey) {
            connection.appendLog("Job suspended at line \(progress?.lastLine ?? 0). Moving to the clearance position.")
            session.sendRawCommand(CNC.clearancePosition.command)
        } else {
            connection.appendLog("Job suspended at line \(progress?.lastLine ?? 0).")
        }
    }

    /// Resumes whichever kind of pause the machine is in. With `line`, first
    /// jumps to that line using the console `goto <line>` command, which the
    /// firmware only accepts while the job is paused.
    func resume(fromLine line: Int? = nil) {
        guard connection.isConnected else { return }
        suspendTask?.cancel()

        let status = connection.status

        if let line, lastUploadedRemotePath != nil, status?.isHeld == true {
            session.sendRawCommand("goto \(line)")
        }

        // Resume the machine first so it's already moving again by the time
        // the runner queues its next line.
        if let status {
            if status.isSuspended {
                session.sendRawCommand(SL.Session.consoleResumeCommand)
                connection.requestStatus()
            } else if status.isFeedHeld {
                _ = connection.sendRealtime(.cycleResume)
                connection.requestStatus()
            }
        }
        jobRunner.resume()
    }

    /// Stops the job outright.
    /// - Mid-upload: cancels the transfer.
    /// - Otherwise: a soft reset, if the machine (or the streamed queue) has
    ///   something in progress. Not resumable.
    func stop() {
        suspendTask?.cancel()
        pendingPlayPath = nil   // cancels a `play` still waiting on pre-run steps
        runAfterUpload = nil

        // Keep what was done so far: a stopped job can still be continued.
        if var record = progress {
            if record.phase == .starting {
                discardProgress()
            } else if record.phase == .running || record.phase == .held || record.phase == .suspended {
                record.markStopped()
                progress = record
                persist(record)
            }
        }

        if uploader.isActive {
            uploader.cancel()
            jobRunner.stop()
            return
        }

        guard connection.isConnected else {
            jobRunner.stop()
            return
        }

        let somethingToAbort = jobRunner.isActive || connection.status?.isBusy == true
        guard somethingToAbort else { return }
        // The session's soft reset also stops the queue and tells the host
        // (`motionAborting`) so held jogs are released.
        session.sendRawCommand(SL.Session.softResetCommand)
    }

    // MARK: - Probing

    /// Probes down at the current XY, then zeroes the work Z coordinate at the
    /// trigger point. The two lines go through `jobRunner`, which only advances
    /// on the previous line's "ok", so the zero lands after the probe stopped.
    func autoZeroProbe() {
        guard connection.isConnected, !jobRunner.isActive else { return }
        jobRunner.start(lines: [
            CNC.probe.with(z: -10, feed: 50).command,
            SL.Session.zeroCommand(z: true)
        ])
    }
}
