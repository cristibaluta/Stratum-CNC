//
//  PerfLog.swift
//  Stratum CNC
//
//  Diagnostics for "the app / the whole Mac freezes after Generate".
//
//  Everything goes to two places:
//    1. A file that survives force-quits and reboots (unbuffered writes):
//         <app container>/Library/Logs/StratumCNC/perf.log
//       The exact path is printed to the Xcode console on first use.
//    2. The unified log (subsystem = bundle id, category "perf"), so it also shows in
//       Console.app / `log show --predicate 'category == "perf"' --last 10m`.
//
//  What gets logged:
//    - explicit events from the pipeline (import, generate, path build, layer assignment)
//    - a heartbeat (about once a second while something is happening, every 10 s when idle):
//      memory footprint (the number Activity Monitor calls "Memory"), process CPU %,
//      thermal state, and aggregated counters (how often / how long canvas.render ran)
//    - "STALL" lines whenever the main thread stops responding for more than 250 ms,
//      including a line while it is *still* blocked (so you see it even if the app never recovers)
//    - memory-pressure and thermal-state changes reported by macOS
//
//  How to read it: if a STALL appears while `cpu` is low, the main thread is *waiting*
//  (typically on Core Animation / the render server), not computing.
//

import Foundation
import os
import Darwin

enum PerfLog {

    // MARK: - Public API

    /// Starts the heartbeat, the watchdog and the system observers. Idempotent; the first
    /// call to any other function does it too.
    static func start() {
        _ = core
    }

    /// `category` is a short tag (gen, path, canvas, import, beat, STALL, system …).
    static func log(_ category: String, _ message: @autoclosure () -> String) {
        core.write(category: category, message: message())
    }

    /// Monotonic timestamp in nanoseconds, for `ms(since:)`.
    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func ms(since start: UInt64) -> Double {
        Double(now() &- start) / 1_000_000
    }

    /// "12.3 ms" / "1.42 s"
    static func fmt(_ milliseconds: Double) -> String {
        milliseconds >= 1000
            ? String(format: "%.2f s", milliseconds / 1000)
            : String(format: "%.1f ms", milliseconds)
    }

    /// Runs `body`, then logs how long it took.
    static func measure<T>(_ category: String, _ label: String, _ body: () throws -> T) rethrows -> T {
        let t0 = now()
        defer { PerfLog.log(category, "\(label): \(fmt(ms(since: t0)))") }
        return try body()
    }

    /// Cheap aggregated counter for things that happen many times a second (render calls,
    /// pan events…). Shown in the heartbeat as `key n=<calls> Σ=<total ms> max=<ms>`.
    static func count(_ key: String, ms: Double = 0) {
        core.count(key, ms: ms)
    }

    /// Logs how long it takes, from now, until the *end of the current main run-loop turn* —
    /// i.e. after Core Animation has committed the layer changes made in this turn.
    /// Call it right after mutating layers. A big number here means the commit blocked the main thread.
    static func logAfterNextRunLoopTurn(_ category: String, _ label: String) {
        let t0 = now()
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,
                                                          CFRunLoopActivity.beforeWaiting.rawValue,
                                                          false,        // one shot
                                                          4_000_000) { _, _ in   // after CA's own commit observer (2_000_000)
            PerfLog.log(category, "\(label): \(fmt(ms(since: t0))) until the end of that run-loop turn (includes the Core Animation commit)")
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    static var logFilePath: String {
        core.fileURL.path
    }

    private static let core = Core()
}

// MARK: - Implementation

private final class Core: @unchecked Sendable {

    let fileURL: URL

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StratumCNC", category: "perf")
    private let fileQueue = DispatchQueue(label: "perflog.file")
    private let timerQueue = DispatchQueue(label: "perflog.timers", qos: .utility)
    private let formatter: DateFormatter
    private var fileHandle: FileHandle?          // only touched on fileQueue (after init)

    // Counters (guarded by `lock`)
    private struct Counter {
        var calls = 0
        var totalMs = 0.0
        var maxMs = 0.0
    }
    private let lock = NSLock()
    private var counters: [String: Counter] = [:]

    // Heartbeat state (only touched on timerQueue)
    private var beatLastWall: UInt64 = 0
    private var beatLastCPU: Double = 0
    private var beatLastLoggedMem: Double = 0
    private var beatQuietTicks = 0

    // Watchdog state (guarded by `lock`)
    private var pingSentAt: UInt64 = 0           // 0 = no ping outstanding
    private var nextBlockedReportMs: Double = 500

    private var timers: [DispatchSourceTimer] = []
    private var memorySource: DispatchSourceMemoryPressure?
    private var thermalObserver: NSObjectProtocol?

    init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/StratumCNC", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let url = logsDir.appendingPathComponent("perf.log")

        // Don't let it grow forever
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
           size > 20_000_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()

        fileURL = url
        fileHandle = handle

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter = f

        let info = ProcessInfo.processInfo
        let ramGB = Double(info.physicalMemory) / 1_073_741_824
        write(category: "session",
              message: "=== started · pid \(getpid()) · \(info.operatingSystemVersionString) · \(info.processorCount) cores · \(String(format: "%.0f", ramGB)) GB RAM · lowPower=\(info.isLowPowerModeEnabled) ===")
        write(category: "session", message: "log file: \(fileURL.path)")
        print("[PerfLog] writing to \(fileURL.path)")

        beatLastWall = DispatchTime.now().uptimeNanoseconds
        beatLastCPU = Self.cpuSeconds()
        beatLastLoggedMem = Self.footprintMB()

        startHeartbeat()
        startWatchdog()
        observeSystem()
    }

    // MARK: Writing

    func write(category: String, message: String) {
        let date = Date()
        let thread = Thread.isMainThread ? "main" : "bg  "
        let mem = Self.footprintMB()
        let cat = category.padding(toLength: 7, withPad: " ", startingAt: 0)
        let body = "[\(thread)] mem=\(Int(mem))MB \(cat) \(message)"

        logger.notice("\(body, privacy: .public)")

        fileQueue.async { [self] in
            let line = "\(formatter.string(from: date)) \(body)\n"
            try? fileHandle?.write(contentsOf: Data(line.utf8))
        }
    }

    // MARK: Counters

    func count(_ key: String, ms: Double) {
        lock.lock()
        var c = counters[key] ?? Counter()
        c.calls += 1
        c.totalMs += ms
        c.maxMs = max(c.maxMs, ms)
        counters[key] = c
        lock.unlock()
    }

    private func drainCounters() -> [String] {
        lock.lock()
        let snapshot = counters
        counters.removeAll(keepingCapacity: true)
        lock.unlock()

        return snapshot
            .sorted { $0.value.totalMs > $1.value.totalMs || ($0.value.totalMs == $1.value.totalMs && $0.key < $1.key) }
            .map { key, c in
                c.totalMs > 0
                    ? "\(key) n=\(c.calls) Σ=\(PerfLog.fmt(c.totalMs)) max=\(PerfLog.fmt(c.maxMs))"
                    : "\(key) n=\(c.calls)"
            }
    }

    // MARK: Heartbeat

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.heartbeatTick()
        }
        timer.resume()
        timers.append(timer)
    }

    private func heartbeatTick() {
        let wallNow = DispatchTime.now().uptimeNanoseconds
        let cpuNow = Self.cpuSeconds()
        let wallSeconds = Double(wallNow - beatLastWall) / 1_000_000_000
        let cpuPercent = wallSeconds > 0 ? (cpuNow - beatLastCPU) / wallSeconds * 100 : 0
        beatLastWall = wallNow
        beatLastCPU = cpuNow

        let activity = drainCounters()
        let mem = Self.footprintMB()
        let memJumped = abs(mem - beatLastLoggedMem) > 25

        beatQuietTicks += 1
        guard !activity.isEmpty || cpuPercent > 40 || memJumped || beatQuietTicks >= 10 else {
            return
        }
        beatQuietTicks = 0
        beatLastLoggedMem = mem

        var text = "cpu=\(String(format: "%.0f", cpuPercent))% thermal=\(Self.thermalName())"
        if !activity.isEmpty {
            text += " | " + activity.joined(separator: " · ")
        }
        write(category: "beat", message: text)
    }

    // MARK: Main-thread watchdog

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.watchdogTick()
        }
        timer.resume()
        timers.append(timer)
    }

    private func watchdogTick() {
        let nowNs = DispatchTime.now().uptimeNanoseconds

        lock.lock()
        let outstanding = pingSentAt
        if outstanding == 0 {
            pingSentAt = nowNs
            nextBlockedReportMs = 500
        }
        let nextReport = nextBlockedReportMs
        lock.unlock()

        if outstanding == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.watchdogPong()
            }
            return
        }

        // A ping is still waiting for the main thread: report while it's happening.
        let blockedMs = Double(nowNs - outstanding) / 1_000_000
        if blockedMs >= nextReport {
            lock.lock()
            nextBlockedReportMs = blockedMs + 2000
            lock.unlock()
            write(category: "STALL", message: "main thread STILL blocked after \(PerfLog.fmt(blockedMs))")
        }
    }

    private func watchdogPong() {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        let sent = pingSentAt
        pingSentAt = 0
        lock.unlock()

        guard sent != 0 else { return }
        let ms = Double(nowNs - sent) / 1_000_000
        if ms > 250 {
            write(category: "STALL", message: "main thread was unresponsive for \(PerfLog.fmt(ms)) (now recovered)")
        }
    }

    // MARK: System notifications

    private func observeSystem() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: timerQueue)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            let name = event.contains(.critical) ? "CRITICAL" : (event.contains(.warning) ? "WARNING" : "normal")
            self?.write(category: "system", message: "memory pressure: \(name)")
        }
        source.resume()
        memorySource = source

        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                                                 object: nil,
                                                                 queue: nil) { [weak self] _ in
            self?.write(category: "system", message: "thermal state changed → \(Self.thermalName())")
        }
    }

    // MARK: Process metrics

    static func thermalName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "SERIOUS"
        case .critical: return "CRITICAL"
        @unknown default: return "unknown"
        }
    }

    /// Process CPU time (user + system), in seconds, summed over all threads.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double {
            Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Physical memory footprint in MB — the number Activity Monitor shows as "Memory".
    /// (If Swift 6 language mode complains about `mach_task_self_`, use `mach_task_self()`.)
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
