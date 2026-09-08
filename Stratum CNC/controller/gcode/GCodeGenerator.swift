//
//  GCodeGenerator.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import AppKit

// MARK: - G-code generation

enum GCodeGenerator {

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

    /// - Parameters: (unchanged params omitted from doc for brevity — see original)
    ///   - ramp: if provided and `enabled`, each pass's plunge ramps in along
    ///     the start of the path instead of dropping straight down. Only
    ///     `.linear` is implemented; `.helix` falls back to a straight plunge
    ///     with a `; NOTE:` comment rather than silently pretending to ramp.
    static func generate(
        subpaths: [[NSPoint]],
        units: Units = .millimeters,
        safeHeightZ: Double = 5.0,
        cutDepthZ: Double = -1.0,
        passDepths: [Double]? = nil,
        feedRateCut: Int = 800,
        feedRatePlunge: Int = 200,
        feedRateRetract: Int? = nil,
        spindleSpeed: Int? = 12000,
        rapidFeedRate: Double? = nil,
        closePathTolerance: Double = 0.001,
        coordinateDecimalPlaces: Int = 2,
        ramp: RampingSettings? = nil,
        preamble: [String] = [],
        postamble: [String] = ["M30 ; program end"]
    ) -> String {

        var lines: [String] = []

        func fmt(_ value: Double) -> String {
            String(format: "%.\(coordinateDecimalPlaces)f", value)
        }

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

        let depths: [Double] = passDepths ?? [cutDepthZ]

        var lastFeedEmitted: Int? = nil

        func emitMove(command: String, x: Double? = nil, y: Double? = nil, z: Double? = nil, feed: Int? = nil) {
            var parts: [String] = [command]
            if let x { parts.append("X\(fmt(x))") }
            if let y { parts.append("Y\(fmt(y))") }
            if let z { parts.append("Z\(fmt(z))") }
            if let feed, feed != lastFeedEmitted {
                parts.append("F\(feed)")
                lastFeedEmitted = feed
            }
            lines.append(parts.joined(separator: " "))
        }

        // MARK: Cutting passes

        var previousDepths = [Double](repeating: 0, count: subpaths.count) // Z0 = top of material
        var warnedHelix = false

        for depth in depths {
            for (subpathIndex, subpath) in subpaths.enumerated() {
                guard let first = subpath.first else { continue }

                var points = subpath
                if let last = points.last, points.count > 1,
                   closePathTolerance > 0,
                   distance(last, first) <= closePathTolerance {
                    points.removeLast()
                    points.append(first)
                }

                let previousDepth = previousDepths[subpathIndex]
                let stepdown = previousDepth - depth // positive: how far this pass must plunge

                emitMove(command: "G0", x: Double(first.x), y: Double(first.y))

                if let ramp, ramp.enabled, ramp.type != .none, points.count > 2, stepdown > 0.0001 {

                    if ramp.type == .helix {
                        if !warnedHelix {
                            lines.append("; NOTE: helix ramping isn't implemented yet — plunging straight instead")
                            warnedHelix = true
                        }
                        emitMove(command: "G1", z: depth, feed: feedRatePlunge)

                    } else { // .linear
                        let outcome = RampMath.linearRampOutcome(angle: ramp.angle, length: ramp.length, stepdown: stepdown)
                        let totalLength = Self.pathLength(points)
                        let usedLength = min(outcome.usedLength, totalLength * 0.9)
                        let (rampPoints, splitSegmentIndex) = Self.rampPrefix(points, distance: usedLength)

                        if !outcome.reachesStepdown || usedLength < outcome.usedLength {
                            lines.append("; WARNING: ramp length \(fmt(ramp.length)) at \(fmt(ramp.angle))deg is short for a \(fmt(stepdown)) stepdown — finishing this pass's plunge straight")
                        }

                        // Ramp down: Z interpolated across the ramp's XY travel.
                        for (point, dist) in rampPoints.dropFirst() {
                            let reachedFraction = min(dist / max(usedLength, 0.0001), 1.0)
                            let z = previousDepth - stepdown * reachedFraction
                            emitMove(command: "G1", x: Double(point.x), y: Double(point.y), z: z, feed: feedRatePlunge)
                        }
                        // Guarantees full depth even if the ramp came up short (warned above).
                        emitMove(command: "G1", z: depth, feed: feedRatePlunge)

                        // Ramp back: retrace the same stretch at full depth.
                        for (point, _) in rampPoints.reversed().dropFirst() {
                            emitMove(command: "G1", x: Double(point.x), y: Double(point.y), feed: feedRateCut)
                        }

                        // Continue the normal cut for the rest of the loop.
                        for point in points[(splitSegmentIndex + 1)...] {
                            emitMove(command: "G1", x: Double(point.x), y: Double(point.y), feed: feedRateCut)
                        }

                        if let feedRateRetract {
                            emitMove(command: "G1", z: safeHeightZ, feed: feedRateRetract)
                        } else {
                            lastFeedEmitted = nil
                            emitMove(command: "G0", z: safeHeightZ)
                        }
                        previousDepths[subpathIndex] = depth
                        continue
                    }
                } else {
                    emitMove(command: "G1", z: depth, feed: feedRatePlunge)
                }

                for point in points.dropFirst() {
                    emitMove(command: "G1", x: Double(point.x), y: Double(point.y), feed: feedRateCut)
                }

                if let feedRateRetract {
                    emitMove(command: "G1", z: safeHeightZ, feed: feedRateRetract)
                } else {
                    lastFeedEmitted = nil
                    emitMove(command: "G0", z: safeHeightZ)
                }

                previousDepths[subpathIndex] = depth
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

    private static func pathLength(_ points: [NSPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 0..<(points.count - 1) {
            total += distance(points[i], points[i + 1])
        }
        return total
    }

    /// Walks `points` from the start, returning the points needed to draw a
    /// ramp of length `distance` (each paired with cumulative distance from
    /// the start), plus the index `i` such that the split falls within
    /// segment `points[i]...points[i+1]` — callers resume normal cutting at
    /// `points[i+1]`.
    private static func rampPrefix(_ points: [NSPoint], distance: Double) -> (points: [(NSPoint, Double)], splitSegmentIndex: Int) {
        guard points.count > 1 else { return ([(points.first ?? .zero, 0)], 0) }

        var result: [(NSPoint, Double)] = [(points[0], 0)]
        var traveled = 0.0

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let segLength = Self.distance(a, b)

            if traveled + segLength >= distance {
                let remaining = distance - traveled
                let t = segLength > 0 ? remaining / segLength : 0
                let split = NSPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
                result.append((split, distance))
                return (result, i)
            }

            traveled += segLength
            result.append((b, traveled))
        }

        return (result, points.count - 2) // distance exceeded the whole path — ramp uses all of it
    }
}
