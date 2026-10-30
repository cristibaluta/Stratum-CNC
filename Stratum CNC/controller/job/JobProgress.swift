//
//  JobProgress.swift
//  Stratum CNC
//
//  What the app remembers about a job it started on the machine, so it can
//  be resumed later, also after the app was closed, the machine was reset
//  or the power was cycled. Pure data plus the rules that follow the machine's
//  reported state; the coordinator feeds it.
//

import Foundation

struct JobProgress: Codable, Equatable {

    enum Phase: String, Codable {
        /// Requested, `play` not yet confirmed by a status report.
        case starting
        case running
        /// Feed hold (`!`).
        case held
        /// Console `suspend`: position saved, spindle stopped.
        case suspended
        /// Stopped from the app (soft reset). Not resumable on the machine;
        /// can be continued with a generated resume file.
        case stopped
        case alarm
        /// The machine went Idle before the program finished.
        case interrupted
    }

    /// The machine's last known position in the program.
    struct Position: Equatable {
        var line: Int
        var percent: Int
    }

    enum Outcome: Equatable {
        case unchanged
        case changed
        /// The program ran to its end: nothing left to resume.
        case completed
        /// The job never really started: forget it.
        case discarded
    }

    var fileName: String
    /// SHA256 of file name + contents (`ControllerModel.fingerprint`). Nil when
    /// the upload happened in an earlier app session and wasn't measured.
    var fingerprint: String?
    /// Path of the program on the machine's SD card.
    var remotePath: String
    /// Where the job's G54 XY origin was set to (the canvas offset), mm.
    var originX: Float
    var originY: Float
    /// Physical line count of the uploaded program. 0 when unknown.
    var totalLines: Int

    /// Last line the machine reported executing (1-based physical file line).
    var lastLine = 0
    var percent = 0
    var phase: Phase = .starting

    /// Set when the program on the machine is a generated resume file: add it
    /// to a reported line to get the line in the original program.
    var lineOffset: Int?

    /// `lastLine` in the original program, also when the machine runs a resume file.
    var sourceLine: Int { lastLine + (lineOffset ?? 0) }

    var startedAt: Date
    var updatedAt: Date
    /// When `play` was sent to the machine.
    var playSentAt: Date?

    init(fileName: String,
         fingerprint: String?,
         remotePath: String,
         originX: Float,
         originY: Float,
         totalLines: Int,
         now: Date = Date()) {
        self.fileName = fileName
        self.fingerprint = fingerprint
        self.remotePath = remotePath
        self.originX = originX
        self.originY = originY
        self.totalLines = totalLines
        self.startedAt = now
        self.updatedAt = now
    }

    /// True when a resume makes sense: the job started and did not finish.
    var isResumable: Bool {
        phase != .starting
    }

    /// Whether the program that is on the machine still is the one loaded now.
    func matches(fingerprint other: String) -> Bool {
        fingerprint == other
    }

    mutating func markPlaySent(at date: Date = Date()) {
        playSentAt = date
        updatedAt = date
    }

    /// How long after `play` an Idle machine means "it never started".
    static let startGrace: TimeInterval = 30

    /// Applies one machine status report.
    ///
    /// - `machineState`: the status state, e.g. "Run", "Hold:0", "Pause", "Idle".
    /// - `active`: playback of a job the machine is running or has paused.
    /// - `frozen`: the last finished or aborted job's numbers, which the
    ///   firmware keeps reporting while Idle.
    ///
    /// Completion is judged by the firmware's own 100%, not by the line count:
    /// the reported line is the last *motion* block, so trailing lines
    /// (`M30`, blanks) leave it short of the last file line. When unsure the
    /// record is kept as `interrupted`, which is harmless; wrongly dropping it
    /// would lose a resumable job.
    mutating func observe(machineState: String,
                          active: Position?,
                          frozen: Position?,
                          now: Date = Date()) -> Outcome {
        let base = machineState.split(separator: ":").first.map(String.init) ?? ""

        switch phase {
        case .starting:
            if let active, let live = Self.livePhase(for: base) {
                phase = live
                record(active, at: now)
                return .changed
            }
            if base == "Idle", let sent = playSentAt, now.timeIntervalSince(sent) > Self.startGrace {
                return .discarded
            }
            return .unchanged

        case .running, .held, .suspended:
            if let live = Self.livePhase(for: base) {
                guard let active else { return .unchanged }
                let before = (phase, lastLine, percent)
                phase = live
                record(active, at: now)
                return before == (phase, lastLine, percent) ? .unchanged : .changed
            }
            switch base {
            case "Alarm":
                phase = .alarm
                updatedAt = now
                return .changed
            case "Idle":
                if let frozen {
                    lastLine = max(lastLine, frozen.line)
                    percent = max(percent, frozen.percent)
                }
                if percent >= 100 {
                    return .completed
                }
                phase = .interrupted
                updatedAt = now
                return .changed
            default:
                return .unchanged
            }

        case .stopped, .alarm, .interrupted:
            return .unchanged
        }
    }

    /// The user stopped the job from the app.
    mutating func markStopped(at date: Date = Date()) {
        phase = .stopped
        updatedAt = date
    }

    private mutating func record(_ position: Position, at date: Date) {
        // The firmware's line never goes backward while a job runs.
        lastLine = max(lastLine, position.line)
        percent = max(percent, position.percent)
        updatedAt = date
    }

    private static func livePhase(for base: String) -> Phase? {
        switch base {
        case "Run": return .running
        case "Hold": return .held
        case "Pause": return .suspended
        default: return nil
        }
    }
}

/// Keeps the one current `JobProgress` on disk. The machine runs one job at
/// a time, so there is a single record.
final class JobProgressStore {

    let fileURL: URL

    init(fileURL: URL = JobProgressStore.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Stratum CNC", isDirectory: true)
            .appendingPathComponent("job-progress.json")
    }

    func load() -> JobProgress? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(JobProgress.self, from: data)
    }

    func save(_ progress: JobProgress) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(progress) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
