//
//  ResumePointResolver.swift
//  Stratum CNC
//
//  Picks a clean line to resume a program from. The line the machine reports
//  is usually in the middle of a cut; restarting there would plunge into the
//  material at that spot and leave a mark. A clean restart point is one where
//  the tool is above the work, so the program's own approach and plunge run
//  again: the start of the pass that was interrupted.
//

import Foundation

struct ResumePoint: Equatable {

    enum Reason: Equatable {
        /// The requested line already is a clean start.
        case exact
        /// Moved back to the last line where the tool was above the work: the
        /// start of the pass that contains the requested line.
        case retractedBeforePass
        /// Moved back to the start of the enclosing toolpath.
        case toolpathStart
        /// Nothing clean before the requested line; it is used as given.
        case none
    }

    var requestedLine: Int
    var line: Int
    var reason: Reason

    var isSnapped: Bool { line != requestedLine }

    /// For the button's help text.
    var explanation: String {
        switch reason {
        case .exact:
            return "Line \(line) is a clean restart point."
        case .retractedBeforePass:
            return "Moved back from line \(requestedLine) to line \(line), where the tool was last above the work: the start of this pass."
        case .toolpathStart:
            return "Moved back from line \(requestedLine) to line \(line), the start of this toolpath."
        case .none:
            return "No clean restart point found before line \(line); the tool may be inside the material when it starts there."
        }
    }
}

/// Built once per program (it reads the whole program), then answers quickly.
struct ResumePointResolver {

    /// 1-based lines of code at which the tool is above the work, ascending.
    private let retractedLines: [Int]
    /// First lines of the analyzed toolpaths, ascending.
    private let toolpathStarts: [Int]
    let lineCount: Int
    /// The lowest Z the program rapids (G0) to: the height it travels at over
    /// the work. Nil when the program has no rapid Z moves.
    let retractZ: Double?

    init(lines: [String], toolpaths: [GCodeToolpath]) {
        lineCount = lines.count
        toolpathStarts = Array(Set(toolpaths.map(\.startLine))).sorted()

        var scanner = GCodeModalScanner()
        var beforeLine: [(line: Int, z: Double?)] = []
        var rapidZs: [Double] = []

        for (index, text) in lines.enumerated() {
            let words = GCodeModalScanner.words(in: text)
            guard !words.isEmpty else { continue }

            beforeLine.append((index + 1, scanner.state.z))
            scanner.apply(text)

            // A rapid Z move in work coordinates tells the travel height.
            let isMachineMove = words.contains { $0.letter == "G" && $0.value == 53 }
            if !isMachineMove,
               words.contains(where: { $0.letter == "Z" }),
               scanner.state.motion == 0,
               let z = scanner.state.z {
                rapidZs.append(z)
            }
        }

        // Z zero is the top of the work in the usual setup, so a rapid Z above
        // zero is a move over the work. A rapid *below* zero (into a hole, say)
        // must not lower the bar, or every line would count as retracted.
        let travel = rapidZs.filter { $0 > 0 }.min() ?? rapidZs.max()
        retractZ = travel
        if let travel {
            retractedLines = beforeLine
                .filter { ($0.z ?? -.infinity) >= travel - 1e-6 }
                .map(\.line)
        } else {
            retractedLines = []
        }
    }

    func resolve(requestedLine: Int) -> ResumePoint {
        guard lineCount > 0 else {
            return ResumePoint(requestedLine: requestedLine, line: requestedLine, reason: .none)
        }
        let requested = min(max(1, requestedLine), lineCount)

        let retracted = Self.lastLine(atOrBefore: requested, in: retractedLines)
        let toolpath = Self.lastLine(atOrBefore: requested, in: toolpathStarts)

        switch (retracted, toolpath) {
        case let (retracted?, toolpath?) where retracted > toolpath:
            return point(requested, retracted, .retractedBeforePass)
        case let (_, toolpath?):
            return point(requested, toolpath, .toolpathStart)
        case let (retracted?, nil):
            return point(requested, retracted, .retractedBeforePass)
        case (nil, nil):
            return ResumePoint(requestedLine: requested, line: requested, reason: .none)
        }
    }

    private func point(_ requested: Int, _ line: Int, _ reason: ResumePoint.Reason) -> ResumePoint {
        ResumePoint(requestedLine: requested, line: line, reason: line == requested ? .exact : reason)
    }

    /// The largest element that is <= `value`, in an ascending array.
    private static func lastLine(atOrBefore value: Int, in sorted: [Int]) -> Int? {
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle] <= value { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : sorted[low - 1]
    }
}
