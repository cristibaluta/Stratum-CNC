//
//  ResumePreamble.swift
//  Stratum CNC
//
//  The lines that put the machine back into the state a program would be in at
//  a given line, so the program can continue from there, plus a builder for a
//  complete resume file (preamble + the rest of the program).
//

import Foundation

struct ResumeOptions: Equatable {
    /// Select the program's tool (`M6 T<n>`) before continuing. On: the
    /// machine ends up with the right tool whatever it holds now. Off: when
    /// the tool is already in the spindle (a bit just replaced by hand).
    var includeToolChange = true
    /// Use this tool instead of the one the program had selected at the resume
    /// line (a different bit chosen after a break).
    var toolOverride: Int?
    /// Wait after starting the spindle, seconds (`G4 P`).
    var spinUpSeconds = 3.0
    /// Feed of the final plunge to the resume depth, mm/min.
    var plungeFeed = 100.0
    /// Height to travel at when nothing in the program says (no Z move found), mm.
    var fallbackSafeZ = 10.0
}

struct ResumePreamble: Equatable {
    /// The lines to run, comments included.
    var lines: [String]
    /// What to tell the person before resuming.
    var warnings: [String]
    /// False when the position at the resume line can't be worked out, in
    /// which case no approach move is generated and resuming is unsafe.
    var canResume: Bool
}

enum ResumePreambleBuilder {

    /// - Parameters:
    ///   - state: The modal state just before the resume line.
    ///   - maxZ: The program's highest Z (mm), used as the travel height.
    static func build(state: GCodeModalState,
                      maxZ: Double?,
                      resumeLine: Int,
                      options: ResumeOptions = ResumeOptions()) -> ResumePreamble {
        var lines = ["; --- Resume preamble: continuing from line \(resumeLine) ---"]
        var warnings = state.warnings

        let toFile = 1 / state.units.scaleToMillimeters
        func number(_ millimeters: Double) -> String { format(millimeters * toFile) }

        // Modal state first, with absolute distances for the approach moves.
        lines.append(state.units == .inches ? "G20" : "G21")
        lines.append("G\(state.plane)")
        if let workspace = state.workspace { lines.append("G\(workspace)") }
        lines.append("G90")

        if options.includeToolChange, let tool = options.toolOverride ?? state.tool {
            lines.append("M6 T\(tool)")
        }

        // Travel height: the program's own clearance, never below where it is now.
        var travelZ = maxZ ?? options.fallbackSafeZ
        if let z = state.z { travelZ = max(travelZ, z) }
        lines.append("G0 Z\(number(travelZ))")

        if state.spindle != .off {
            let code = state.spindle == .clockwise ? "M3" : "M4"
            if let speed = state.spindleSpeed {
                lines.append("\(code) S\(format(speed))")
            } else {
                lines.append(code)
                warnings.append("The program starts the spindle without a speed (S) before this line.")
            }
            if options.spinUpSeconds > 0 {
                lines.append("G4 P\(format(options.spinUpSeconds))")
            }
        }
        if state.airflow { lines.append("M7") }

        var canResume = true
        if let x = state.x, let y = state.y {
            lines.append("G0 X\(number(x)) Y\(number(y))")
        } else {
            canResume = false
            warnings.append("The XY position at this line can't be worked out from the program (relative moves from an unknown start, or G28).")
        }

        if let z = state.z {
            if z < travelZ {
                lines.append("G1 Z\(number(z)) F\(format(options.plungeFeed * toFile))")
            }
        } else {
            canResume = false
            warnings.append("The Z height at this line can't be worked out from the program.")
        }

        // Back to what the program expects.
        if let feed = state.feed { lines.append("F\(format(feed))") }
        if let motion = state.motion { lines.append("G\(motion)") }
        if !state.absolute { lines.append("G91") }
        lines.append("; --- End of resume preamble ---")

        return ResumePreamble(lines: lines, warnings: warnings, canResume: canResume)
    }

    /// Up to four decimals, no trailing zeros, always a dot.
    static func format(_ value: Double) -> String {
        var text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
}

/// A complete program that continues another one from a given line.
struct ResumeFile: Equatable {
    var contents: String
    /// The resume line in the original program.
    var resumeLine: Int
    var preamble: ResumePreamble
    /// Add this to a line number the machine reports for the resume file to get
    /// the line in the original program. (Lines before the first original line
    /// are the preamble; they map to numbers before `resumeLine`.)
    var lineOffset: Int

    func originalLine(forResumeFileLine line: Int) -> Int {
        line + lineOffset
    }
}

enum ResumeFileBuilder {

    /// Builds a file that runs `lines` from `resumeLine` (1-based) to the end,
    /// preceded by the preamble. Nil for an empty program.
    static func build(lines: [String],
                      resumeLine: Int,
                      options: ResumeOptions = ResumeOptions()) -> ResumeFile? {
        guard !lines.isEmpty else { return nil }
        let line = min(max(1, resumeLine), lines.count)

        let (state, maxZ) = GCodeModalState.scan(lines: lines, beforeLine: line)
        let preamble = ResumePreambleBuilder.build(state: state, maxZ: maxZ,
                                                   resumeLine: line, options: options)

        let prefix = preamble.lines
        let body = Array(lines[(line - 1)...])
        let contents = (prefix + body).joined(separator: "\n")

        return ResumeFile(contents: contents,
                          resumeLine: line,
                          preamble: preamble,
                          lineOffset: line - 1 - prefix.count)
    }
}
