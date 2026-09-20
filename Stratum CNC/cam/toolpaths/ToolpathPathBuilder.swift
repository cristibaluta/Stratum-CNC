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
    static func path(for outputs: [SC.OutputToolpath]) -> CGPath? {

        var pen = Pen()

        for output in outputs {
            for pass in output.passes {
                var current: CGPoint?

                for waypoint in pass.waypoints {
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

        return pen.path.isEmpty ? nil : pen.path
    }

    /// Draws connected moves as one subpath, starting a new one only when the
    /// tool jumped (rapid / retract) since the last segment ended.
    private struct Pen {

        let path = CGMutablePath()
        private var last: CGPoint?

        mutating func line(from: CGPoint, to: CGPoint) {
            begin(at: from)
            path.addLine(to: to)
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
        }
    }
}
