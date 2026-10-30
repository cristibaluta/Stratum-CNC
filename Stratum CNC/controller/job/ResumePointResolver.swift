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
import simd

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
        /// Moved back along the cut by the given distance (mm), but not past
        /// the start of the pass.
        case backedUp(millimeters: Double)
        /// The exact line the person asked for, used as given.
        case chosen
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
        case .chosen:
            return "Restarting at line \(line), as chosen. The tool is not necessarily above the work there."
        case .backedUp(let millimeters):
            let distance = ResumePreambleBuilder.format(millimeters)
            return line == requestedLine
                ? "Line \(line) is where the cut started; there is nothing to back up over."
                : "Moved back \(distance) mm along the cut, from line \(requestedLine) to line \(line)."
        }
    }
}

/// Built once per program (it reads the whole program), then answers quickly.
struct ResumePointResolver {

    /// 1-based lines of code at which the tool is above the work, ascending.
    private let retractedLines: [Int]
    /// First lines of the analyzed toolpaths, ascending.
    private let toolpathStarts: [Int]
    /// Length of the cutting moves (G1/G2/G3) run before each line, mm,
    /// indexed by 1-based line number (index 0 is unused). Non-decreasing.
    /// Arcs count as their chord, so curves are slightly underestimated.
    private let cutLengthBefore: [Double]
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
        var cutLength = 0.0
        var cutLengths: [Double] = [0]
        var previousPosition: SIMD3<Double>?

        for (index, text) in lines.enumerated() {
            cutLengths.append(cutLength)

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

            // Length of cutting moves, for "back up N mm".
            let state = scanner.state
            if let x = state.x, let y = state.y, let z = state.z {
                let position = SIMD3<Double>(x, y, z)
                if let previousPosition, !isMachineMove,
                   let motion = state.motion, (1...3).contains(motion) {
                    cutLength += simd_distance(previousPosition, position)
                }
                previousPosition = position
            } else {
                previousPosition = nil
            }
        }
        cutLengthBefore = cutLengths

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

    /// Backs up `millimeters` along the cut from `requestedLine`, never past the
    /// start of the pass it belongs to (a restart must not cross a retract).
    /// Use this after a bit broke: the broken bit may have left the last
    /// stretch of the cut unfinished, so restart a little earlier than where it
    /// stopped. Lands on a line inside the cut, so the preamble plunges to the
    /// cut depth right there.
    func backedUp(from requestedLine: Int, millimeters: Double) -> ResumePoint {
        guard lineCount > 0 else {
            return ResumePoint(requestedLine: requestedLine, line: requestedLine,
                               reason: .backedUp(millimeters: millimeters))
        }
        let requested = min(max(1, requestedLine), lineCount)
        let passStart = resolve(requestedLine: requested).line
        let target = cutLengthBefore[requested] - max(0, millimeters)

        // Largest line in passStart...requested whose cut length before it is <= target.
        var low = passStart
        var high = requested + 1
        while low < high {
            let middle = (low + high) / 2
            if cutLengthBefore[middle] <= target { low = middle + 1 } else { high = middle }
        }
        let line = max(passStart, low - 1)
        return ResumePoint(requestedLine: requested, line: min(line, requested),
                           reason: .backedUp(millimeters: millimeters))
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
