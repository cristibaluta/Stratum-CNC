//
//  ToolSchedule.swift
//  Stratum CNC
//
//  Which tool is in the spindle on each line of a program, so the heightmap
//  carves every segment with the tool that actually cut it instead of one
//  tool for the whole file.
//

import Foundation

struct ToolSchedule: Equatable, Sendable {

    /// From `fromLine` (1-based, inclusive) on, `tool` is in the spindle. `nil` means the tool
    /// called there has no assignment yet: its segments carve nothing, rather than guessing a size.
    struct Entry: Equatable, Sendable {
        let fromLine: UInt32
        let tool: ToolGeometry?
    }

    /// Ascending by `fromLine`.
    let entries: [Entry]

    /// The tool for lines before the first entry — a program that never changes tool, or the
    /// setup lines ahead of its first `T… M6`.
    let initial: ToolGeometry?

    init(initial: ToolGeometry?, entries: [Entry] = []) {
        self.initial = initial
        self.entries = entries
    }

    /// One tool for the whole program.
    static func single(_ tool: ToolGeometry?) -> ToolSchedule {
        ToolSchedule(initial: tool)
    }

    /// True when no line has a tool to carve with.
    var isEmpty: Bool {
        initial == nil && entries.allSatisfy { $0.tool == nil }
    }

    /// The tool in the spindle at `line`: that of the last entry at or before it.
    func tool(atLine line: UInt32) -> ToolGeometry? {
        // Binary search for the last entry with `fromLine <= line`.
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].fromLine <= line {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? initial : entries[low - 1].tool
    }
}
