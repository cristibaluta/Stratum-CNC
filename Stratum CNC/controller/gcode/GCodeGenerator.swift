//
//  GCodeGenerator.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import AppKit

// MARK: - G-code generation

enum GCodeGenerator {

    /// Units the G-code output should declare and assume all numeric
    /// parameters (feeds, depths, Z heights) are expressed in.
    enum Units {
        case millimeters
        case inches

        var gcodeHeader: String {
            switch self {
            case .millimeters: return "G21 ; millimeters"
            case .inches: return "G20 ; inches"
            }
        }
    }

    /// Generates a complete G-code program from an array of subpaths
    /// (each subpath an array of NSPoint, e.g. from BezierPathFlattener).
    ///
    /// - Parameters:
    ///   - subpaths: array of point arrays, one per continuous cut path.
    ///   - units: mm or inches — must match the units your points/depths/feeds are in.
    ///   - safeHeightZ: Z height for rapid travel between cuts. Must clear all clamps/stock.
    ///   - cutDepthZ: Z height (typically negative) the tool plunges down to for cutting.
    ///     Pass a single final depth here; for multi-pass depth-of-cut, see `passDepths`.
    ///   - passDepths: optional explicit list of Z depths to cut at, in order
    ///     (e.g. [-1.0, -2.0, -3.0] to rough down in three passes). If provided,
    ///     this overrides `cutDepthZ` and each subpath is fully retraced at every
    ///     depth before moving to the next subpath. If nil, `cutDepthZ` is used once.
    ///   - feedRateCut: feedrate (units/min) for lateral cutting moves (G1 X Y).
    ///   - feedRatePlunge: feedrate (units/min) for the vertical plunge move (G1 Z).
    ///     Usually significantly slower than feedRateCut to avoid tool/machine strain.
    ///   - feedRateRetract: feedrate for the retract move. If nil, retract is done
    ///     as a rapid (G0) instead of a controlled feed — fine for air moves with
    ///     no obstructions above the stock; use a feed here instead if you need a
    ///     controlled vertical exit (e.g. very deep or fragile setups).
    ///   - spindleSpeed: RPM for M3 spindle-on command. Pass nil to omit spindle
    ///     control entirely (e.g. for a laser or plotter setup).
    ///   - rapidFeedRate: informational only — most controllers use a fixed max
    ///     rapid rate (G0 doesn't take an F parameter). Included so you can
    ///     document/comment it, or use it for time estimation elsewhere.
    ///   - closePathTolerance: if the last point of a subpath is within this
    ///     distance of the first point, treated as already closed (avoids a
    ///     redundant zero-length final move). Set to 0 to disable the check.
    ///   - coordinateDecimalPlaces: rounding precision for emitted X/Y/Z values.
    ///   - preamble: extra raw G-code lines inserted after the units/positioning
    ///     setup and before the first move (e.g. work offset G54, tool number).
    ///   - postamble: extra raw G-code lines appended at the very end, after
    ///     spindle-off and final retract (e.g. program end M30).
    /// - Returns: the full G-code program as a newline-separated string.
    static func generate(
        subpaths: [[NSPoint]],
        units: Units = .millimeters,
        safeHeightZ: Double = 5.0,
        cutDepthZ: Double = -1.0,
        passDepths: [Double]? = nil,
        feedRateCut: Double = 800,
        feedRatePlunge: Double = 200,
        feedRateRetract: Double? = nil,
        spindleSpeed: Int? = 12000,
        rapidFeedRate: Double? = nil,
        closePathTolerance: Double = 0.001,
        coordinateDecimalPlaces: Int = 4,
        preamble: [String] = [],
        postamble: [String] = ["M30 ; program end"]
    ) -> String {

        var lines: [String] = []

        func fmt(_ value: Double) -> String {
            String(format: "%.\(coordinateDecimalPlaces)f", value)
        }

        // MARK: Header

        lines.append(units.gcodeHeader)
        lines.append("G90 ; absolute positioning")
        lines.append("G17 ; XY plane")
        if let rapidFeedRate {
            lines.append("; rapid feedrate reference: \(fmt(rapidFeedRate)) units/min (informational — G0 uses machine max)")
        }
        lines.append(contentsOf: preamble)

        if let spindleSpeed {
            lines.append("M3 S\(spindleSpeed) ; spindle on")
        }

        lines.append("G0 Z\(fmt(safeHeightZ)) ; retract to safe height before starting")

        // MARK: Determine depth passes

        let depths: [Double] = passDepths ?? [cutDepthZ]

        var lastFeedEmitted: Double? = nil

        func emitMove(command: String, x: Double? = nil, y: Double? = nil, z: Double? = nil, feed: Double? = nil) {
            var parts: [String] = [command]
            if let x { parts.append("X\(fmt(x))") }
            if let y { parts.append("Y\(fmt(y))") }
            if let z { parts.append("Z\(fmt(z))") }
            if let feed, feed != lastFeedEmitted {
                parts.append("F\(fmt(feed))")
                lastFeedEmitted = feed
            }
            lines.append(parts.joined(separator: " "))
        }

        // MARK: Cutting passes

        for depth in depths {
            for subpath in subpaths {
                guard let first = subpath.first else { continue }

                // Normalize: drop a redundant final point that just re-closes the start.
                var points = subpath
                if let last = points.last, points.count > 1,
                   closePathTolerance > 0,
                   distance(last, first) <= closePathTolerance {
                    points.removeLast()
                    points.append(first) // keep an explicit close, but only one
                }

                // Rapid to start of this subpath at safe height.
                emitMove(command: "G0", x: Double(first.x), y: Double(first.y))

                // Plunge down to this pass's cut depth.
                emitMove(command: "G1", z: depth, feed: feedRatePlunge)

                // Cut along every subsequent point at cutting feed.
                for point in points.dropFirst() {
                    emitMove(command: "G1", x: Double(point.x), y: Double(point.y), feed: feedRateCut)
                }

                // Retract to safe height before moving to the next subpath.
                if let feedRateRetract {
                    emitMove(command: "G1", z: safeHeightZ, feed: feedRateRetract)
                } else {
                    lastFeedEmitted = nil // G0 carries no feed; next G1 must re-declare F
                    emitMove(command: "G0", z: safeHeightZ)
                }
            }
        }

        // MARK: Footer

        if spindleSpeed != nil {
            lines.append("M5 ; spindle off")
        }
        lines.append(contentsOf: postamble)

        return lines.joined(separator: "\n")
    }

    private static func distance(_ a: NSPoint, _ b: NSPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - Usage example

/*
let subpaths = BezierPathFlattener.flatten(svgPaths, tolerance: 0.05) // mm

let gcode = GCodeGenerator.generate(
    subpaths: subpaths,
    units: .millimeters,
    safeHeightZ: 5.0,
    cutDepthZ: -2.0,
    feedRateCut: 900,
    feedRatePlunge: 150,
    spindleSpeed: 15000
)

print(gcode)
// or write to disk:
// try? gcode.write(toFile: "/path/to/output.nc", atomically: true, encoding: .utf8)
*/

/*
Example with multi-pass depth of cut, cutting the same outlines three times
at increasing depth to rough out a 3mm-deep pocket outline in 1mm passes:

let gcode = GCodeGenerator.generate(
    subpaths: subpaths,
    passDepths: [-1.0, -2.0, -3.0],
    feedRateCut: 900,
    feedRatePlunge: 150
)
*/
