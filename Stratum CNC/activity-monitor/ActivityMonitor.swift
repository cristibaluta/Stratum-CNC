//
//  ActivityMonitor.swift
//  Stratum CNC
//
//  Samples this app's CPU, memory and thermal state once a second and keeps the last minute,
//  for `ActivityMonitorView`. It is the live counterpart of the heartbeat lines `PerfLog` can
//  write (see `PerfLog.heartbeatLoggingEnabled`).
//

import Foundation

struct ActivitySample: Equatable {
    /// Share of one core, like Activity Monitor: 100 is one core fully busy, so it can go above 100.
    var cpuPercent: Double
    var memoryMB: Double
    var thermal: ProcessInfo.ThermalState

    /// Whether `other` would look different in the toolbar: CPU or memory moved by a couple of
    /// units, the thermal state changed, or CPU crossed between idle and not idle. Used so an idle
    /// app doesn't redraw its toolbar every second for a jitter of 1%.
    func differsVisibly(from other: ActivitySample) -> Bool {
        abs(cpuPercent - other.cpuPercent) >= 2
            || (cpuPercent < 1) != (other.cpuPercent < 1)
            || abs(memoryMB - other.memoryMB) >= 2
            || thermal != other.thermal
    }

    static var current: ActivitySample {
        ActivitySample(cpuPercent: 0,
                       memoryMB: ProcessMetrics.footprintMB(),
                       thermal: ProcessInfo.processInfo.thermalState)
    }
}

@MainActor
final class ActivityMonitor: ObservableObject {

    /// How many one-second samples are kept.
    static let historyLength = 60

    /// What the toolbar shows. Published only when it would look different (see
    /// `ActivitySample.differsVisibly`): every update redraws a toolbar item, and on macOS that
    /// relayouts the whole toolbar, which costs real CPU when done every second at idle.
    @Published private(set) var latest: ActivitySample

    /// The last minute, oldest first; never empty. Not published: the popover polls it once a
    /// second while it is open, and nothing else reads it.
    private(set) var samples: [ActivitySample]

    private var lastWall = DispatchTime.now().uptimeNanoseconds
    private var lastCPUSeconds = ProcessMetrics.cpuSeconds()

    init() {
        let first = ActivitySample.current
        latest = first
        samples = [first]
    }

    /// Samples every second until the calling task is cancelled. Run it from a view's `.task`, so
    /// it stops with the view.
    func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            sample()
        }
    }

    private func sample() {
        let wall = DispatchTime.now().uptimeNanoseconds
        let cpuSeconds = ProcessMetrics.cpuSeconds()
        let elapsed = Double(wall &- lastWall) / 1_000_000_000
        let cpu = elapsed > 0 ? max(0, (cpuSeconds - lastCPUSeconds) / elapsed * 100) : 0
        lastWall = wall
        lastCPUSeconds = cpuSeconds

        let sample = ActivitySample(cpuPercent: cpu,
                                    memoryMB: ProcessMetrics.footprintMB(),
                                    thermal: ProcessInfo.processInfo.thermalState)
        samples.append(sample)
        if samples.count > Self.historyLength {
            samples.removeFirst(samples.count - Self.historyLength)
        }
        if sample.differsVisibly(from: latest) {
            latest = sample
        }
    }
}
