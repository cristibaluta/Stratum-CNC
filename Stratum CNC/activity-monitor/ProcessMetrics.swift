//
//  ProcessMetrics.swift
//  Stratum CNC
//
//  The numbers Activity Monitor shows for this process: memory, CPU time and the thermal state.
//  Shared by `ActivityMonitor` (the toolbar view) and `PerfLog` (the diagnostics log).
//

import Foundation
import Darwin

enum ProcessMetrics {

    static func thermalName(_ state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) -> String {
        switch state {
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
