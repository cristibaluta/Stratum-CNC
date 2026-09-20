//
//  GCodeBounds.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//

import Foundation

/// The XY area (millimeters, in the program's own work coordinates) that a
/// program actually *cuts* — used to size the auto-leveling probe grid so it
/// covers the material being machined and not the whole bed.
///
/// Only feed moves count (G1/G2/G3 and canned drilling cycles). Rapids are
/// tracked to know where the tool is, but are left out of the extent: a
/// `G0 X0 Y0` parking move at the end of a program would otherwise stretch
/// the grid to the origin even when the part is far from it.
///
/// Deliberately small, not a full G-code interpreter: it assumes the XY
/// plane (G17), reads arcs in I/J form (R-form arcs contribute only their
/// endpoint), skips G28/G30/G53 lines, and understands G20/G21 and G90/G91.
/// `nil` means nothing measurable was found.
struct GCodeBounds: Equatable {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }

    static func cutting(in gcode: String) -> GCodeBounds? {
        var tracker = Tracker()
        gcode.enumerateLines { line, _ in tracker.consume(line) }
        return tracker.result
    }
}

private struct Tracker {

    private static let wordRegex = try! NSRegularExpression(
        pattern: #"([A-Za-z])\s*([-+]?(?:\d+\.?\d*|\.\d+))"#
    )
    private static let parenComment = try! NSRegularExpression(pattern: #"\([^)]*\)"#)

    // Where the tool currently is (nil until the program says).
    private var x: Double?
    private var y: Double?

    private var relative = false
    private var scale = 1.0          // 25.4 while G20 is active
    private var motion: Int?         // modal: 0, 1, 2, 3, or 81...89

    private var minX: Double?
    private var maxX: Double?
    private var minY: Double?
    private var maxY: Double?

    var result: GCodeBounds? {
        guard let minX, let maxX, let minY, let maxY else { return nil }
        return GCodeBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    mutating func consume(_ rawLine: String) {
        let words = Self.words(in: rawLine)
        guard !words.isEmpty else { return }

        var wordX: Double?, wordY: Double?, wordZ: Double?
        var wordI: Double?, wordJ: Double?

        for (letter, value) in words {
            switch letter {
                case "G":
                    // Homing / machine-coordinate lines say nothing about
                    // where the work is.
                    if value == 28 || value == 30 || value == 53 { return }
                    switch value {
                        case 0, 1, 2, 3: motion = Int(value)
                        case 80: motion = nil
                        case 81...89 where value == value.rounded(): motion = Int(value)
                        case 90: relative = false
                        case 91: relative = true
                        case 20: scale = 25.4
                        case 21: scale = 1.0
                        default: break
                    }
                case "X": wordX = value * scale
                case "Y": wordY = value * scale
                case "Z": wordZ = value
                case "I": wordI = value * scale
                case "J": wordJ = value * scale
                default: break
            }
        }

        // Target position after this line.
        var newX = x, newY = y
        if let wordX { newX = relative ? x.map { $0 + wordX } : wordX }
        if let wordY { newY = relative ? y.map { $0 + wordY } : wordY }

        let hasAxisWord = wordX != nil || wordY != nil || wordZ != nil
        if let motion, motion != 0, hasAxisWord {
            // A cutting move. Include where it starts as well as where it
            // ends: the plunge (a Z-only feed move) carries no X/Y words but
            // is still cutting at the current XY.
            include(x: x, y: y)

            if motion == 2 || motion == 3,
               let sx = x, let sy = y, let ex = newX, let ey = newY,
               wordI != nil || wordJ != nil {
                includeArc(from: (sx, sy), to: (ex, ey),
                           i: wordI ?? 0, j: wordJ ?? 0,
                           clockwise: motion == 2)
            } else {
                include(x: newX, y: newY)
            }
        }

        x = newX
        y = newY
    }

    // MARK: - Extent

    private mutating func include(x px: Double?, y py: Double?) {
        if let px {
            minX = Swift.min(minX ?? px, px)
            maxX = Swift.max(maxX ?? px, px)
        }
        if let py {
            minY = Swift.min(minY ?? py, py)
            maxY = Swift.max(maxY ?? py, py)
        }
    }

    /// Adds an arc's endpoints plus any of its four extreme points (the
    /// cardinal directions from the center) that the arc sweeps through —
    /// a half circle bulges past both of its endpoints.
    private mutating func includeArc(from start: (Double, Double), to end: (Double, Double),
                                     i: Double, j: Double, clockwise: Bool) {
        let cx = start.0 + i
        let cy = start.1 + j
        let radius = hypot(i, j)
        let twoPi = 2 * Double.pi

        func wrap(_ angle: Double) -> Double {
            let m = angle.truncatingRemainder(dividingBy: twoPi)
            return m < 0 ? m + twoPi : m
        }

        let a0 = atan2(start.1 - cy, start.0 - cx)
        let a1 = atan2(end.1 - cy, end.0 - cx)

        // Angular length of the arc; identical start/end means a full circle.
        var sweep = wrap(clockwise ? a0 - a1 : a1 - a0)
        if sweep < 1e-9 { sweep = twoPi }

        include(x: start.0, y: start.1)
        include(x: end.0, y: end.1)

        for quadrant in 0..<4 {
            let theta = Double(quadrant) * Double.pi / 2
            let delta = wrap(clockwise ? a0 - theta : theta - a0)
            if delta <= sweep {
                include(x: cx + radius * cos(theta), y: cy + radius * sin(theta))
            }
        }
    }

    // MARK: - Parsing

    private static func words(in rawLine: String) -> [(Character, Double)] {
        var text = rawLine
        if let semicolon = text.firstIndex(of: ";") {
            text = String(text[..<semicolon])
        }
        let full = NSRange(text.startIndex..., in: text)
        text = parenComment.stringByReplacingMatches(in: text, range: full, withTemplate: " ")

        let range = NSRange(text.startIndex..., in: text)
        return wordRegex.matches(in: text, range: range).compactMap { match in
            guard let letterRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text),
                  let letter = text[letterRange].uppercased().first,
                  let value = Double(text[valueRange]) else { return nil }
            return (letter, value)
        }
    }
}
