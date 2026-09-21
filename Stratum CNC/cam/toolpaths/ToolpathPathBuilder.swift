//
//  ToolpathPathBuilder.swift
//  Stratum CNC
//
//  Flattens generated toolpaths into a single top-down (XY) CGPath, in world
//  coordinates, for drawing on the 2D canvas.
//

import Foundation
import CoreGraphics
import StratumCAM

enum ToolpathPathBuilder {

    /// Max distance between an arc and the straight chords approximating it (mm).
    private static let chordTolerance: Double = 0.01

    /// Every pass of every toolpath as one path. Only cutting moves are drawn:
    /// rapids are skipped, and so are pure Z moves (plunges/retracts), which
    /// have no XY extent. Returns nil if there's nothing to draw.
    ///
    /// Seen from above, most passes of a profile cut are the same line at a
    /// different depth (30 passes at 0.1 mm stepdown = 30 copies), so a pass
    /// whose XY geometry was already drawn is skipped. That cuts the path —
    /// and the cost of building and stroking it — by the pass count.
    static func path(for outputs: [SC.OutputToolpath]) -> CGPath? {

        let t0 = PerfLog.now()
        var pen = Pen()
        var drawnPasses = Set<Int>()

        // Diagnostics
        var totalPasses = 0
        var skippedPasses = 0
        var waypointsVisited = 0
        var nonFinitePoints = 0
        var drawnPassWaypointCounts: [Int] = []

        for output in outputs {
            for pass in output.passes {
                totalPasses += 1
                guard drawnPasses.insert(signature(of: pass)).inserted else {
                    skippedPasses += 1
                    continue
                }
                drawnPassWaypointCounts.append(pass.waypoints.count)

                var current: CGPoint?

                for waypoint in pass.waypoints {
                    waypointsVisited += 1
                    if !(waypoint.position.x.isFinite && waypoint.position.y.isFinite) {
                        nonFinitePoints += 1
                    }

                    let target = CGPoint(x: waypoint.position.x, y: waypoint.position.y)
                    let from = current ?? target
                    current = target

                    switch waypoint.motion {
                    case .rapid:
                        break

                    case .linear:
                        if hypot(target.x - from.x, target.y - from.y) > 1e-9 {
                            pen.line(from: from, to: target)
                        }

                    case .arcCW(let center):
                        pen.arc(from: from, to: target, center: center, isCCW: false)

                    case .arcCCW(let center):
                        pen.arc(from: from, to: target, center: center, isCCW: true)
                    }
                }
            }
        }

        let result: CGPath? = pen.path.isEmpty ? nil : pen.path

        // Diagnostics
        let bounds = pen.path.boundingBoxOfPath
        let boundsText = bounds.isNull
            ? "empty"
            : String(format: "x %.1f…%.1f, y %.1f…%.1f mm (%.1f × %.1f)",
                     bounds.minX, bounds.maxX, bounds.minY, bounds.maxY, bounds.width, bounds.height)
        PerfLog.log("path", "preview built in \(PerfLog.fmt(PerfLog.ms(since: t0))): passes \(totalPasses) total → "
                    + "\(drawnPasses.count) unique drawn, \(skippedPasses) skipped as duplicates · "
                    + "waypoints visited \(waypointsVisited)")
        PerfLog.log("path", "preview path: \(pen.moves) moveTo + \(pen.lines) lineTo "
                    + "(\(pen.arcs) arcs flattened into \(pen.arcSegments) segments) · bbox \(boundsText)")
        if drawnPasses.count > 1 {
            PerfLog.log("path", "unique passes drawn — waypoints per pass (first 8): \(Array(drawnPassWaypointCounts.prefix(8)))")
        }
        if totalPasses > 3 && skippedPasses == 0 {
            PerfLog.log("path", "⚠️ no pass was a duplicate of another — the XY dedupe removed nothing, "
                        + "so the overlay holds all \(totalPasses) passes")
        }
        if nonFinitePoints > 0 {
            PerfLog.log("path", "⚠️ \(nonFinitePoints) waypoint(s) with NaN/infinite X or Y")
        }

        return result
    }

    /// A hash of the pass's XY moves (Z ignored), to spot passes that would
    /// draw exactly the same line. Coordinates are quantized to 0.1 µm.
    private static func signature(of pass: SC.ToolpathPass) -> Int {

        func q(_ value: Double) -> Int {
            Int((value * 10_000).rounded())
        }

        var hasher = Hasher()
        for waypoint in pass.waypoints {
            switch waypoint.motion {
            case .rapid:
                hasher.combine(0)
            case .linear:
                hasher.combine(1)
            case .arcCW(let center):
                hasher.combine(2)
                hasher.combine(q(center.x))
                hasher.combine(q(center.y))
            case .arcCCW(let center):
                hasher.combine(3)
                hasher.combine(q(center.x))
                hasher.combine(q(center.y))
            }
            hasher.combine(q(waypoint.position.x))
            hasher.combine(q(waypoint.position.y))
        }
        return hasher.finalize()
    }

    /// Draws connected moves as one subpath, starting a new one only when the
    /// tool jumped (rapid / retract) since the last segment ended.
    private struct Pen {

        let path = CGMutablePath()
        private var last: CGPoint?

        // Diagnostics: what actually ended up in `path`
        private(set) var moves = 0
        private(set) var lines = 0
        private(set) var arcs = 0
        private(set) var arcSegments = 0

        mutating func line(from: CGPoint, to: CGPoint) {
            begin(at: from)
            path.addLine(to: to)
            lines += 1
            last = to
        }

        /// Arcs are flattened here instead of using `CGPath.addArc`, whose
        /// `clockwise` flag flips meaning with the coordinate system — this way
        /// direction is unambiguous, and a full circle (start == end) works.
        mutating func arc(from: CGPoint, to: CGPoint, center: CGPoint, isCCW: Bool) {

            let radius = hypot(from.x - center.x, from.y - center.y)
            guard radius > 1e-9 else {
                line(from: from, to: to)
                return
            }

            let startAngle = atan2(from.y - center.y, from.x - center.x)
            let endAngle = atan2(to.y - center.y, to.x - center.x)

            // Sweep in the direction of travel, in (0, 2π]. A zero sweep means
            // a full circle, as emitted for circular contours.
            var sweep = (isCCW ? endAngle - startAngle : startAngle - endAngle)
                .truncatingRemainder(dividingBy: 2 * .pi)
            if sweep < 1e-9 {
                sweep += 2 * .pi
            }
            let direction: Double = isCCW ? 1 : -1

            let chordAngle = 2 * acos(max(-1, 1 - ToolpathPathBuilder.chordTolerance / radius))
            let step = max(min(chordAngle, .pi / 8), 1e-3)
            let steps = max(1, Int((sweep / step).rounded(.up)))

            arcs += 1
            arcSegments += steps
            lines += steps
            begin(at: from)
            for i in 1..<steps {
                let angle = startAngle + direction * sweep * Double(i) / Double(steps)
                path.addLine(to: CGPoint(x: center.x + radius * cos(angle),
                                         y: center.y + radius * sin(angle)))
            }
            path.addLine(to: to)
            last = to
        }

        private mutating func begin(at point: CGPoint) {
            if let last, hypot(last.x - point.x, last.y - point.y) <= 1e-6 {
                return
            }
            path.move(to: point)
            moves += 1
        }
    }
}
