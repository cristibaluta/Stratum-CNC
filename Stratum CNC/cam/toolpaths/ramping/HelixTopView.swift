//
//  HelixTopView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

struct HelixTopView: View {
    let angle: Double
    let length: Double
    var direction: HelixDirection = .outsideIn
    private let cycleDuration: Double = 3.0
    /// Reference diameter (mm) that fills the available drawing area — same
    /// convention as the linear and zig-zag views, so `length` visibly
    /// changes the spiral size instead of being ignored.
    private let referenceLength: Double = 30
    /// Raised from 0.35 so small diameters still fill most of the frame —
    /// previously the spiral could shrink to just over a third of the
    /// available space, leaving a lot of dead canvas around it.
    private let minSizeFraction: CGFloat = 0.7

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = spiralPoints(in: size)
            TimelineView(.animation) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)
                Canvas { context, _ in
                    draw(context: &context, size: size, points: points, phase: currentPhase)
                }
            }
        }
    }

    /// Outer spiral radius, scaled by `length` relative to `referenceLength`
    /// (capped at the available canvas radius either way).
    private func outerRadius(in size: CGSize) -> CGFloat {
        let maxRadius = min(size.width, size.height) / 2 - 2
        let sizeFraction = min(max(CGFloat(length / referenceLength), minSizeFraction), 1.0)
        return maxRadius * sizeFraction
    }

    private func spiralPoints(in size: CGSize) -> [CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = outerRadius(in: size)
        let innerRadius = outerRadius * 0.55
        let turns = RampMath.helixTurns(angle: angle)
        let pointsPerTurn = 40
        let totalPoints = turns * pointsPerTurn
        // Start/end radius flip with direction; `t` still runs 0 → 1 as the
        // cut progresses, so the depth-fade in `draw` stays correct either way.
        let startRadius = direction == .outsideIn ? outerRadius : innerRadius
        let endRadius = direction == .outsideIn ? innerRadius : outerRadius
        return (0...totalPoints).map { i in
            let t = CGFloat(i) / CGFloat(totalPoints)
            let radius = startRadius + (endRadius - startRadius) * t
            let theta = t * CGFloat(turns) * 2 * .pi
            return CGPoint(
                x: center.x + radius * cos(theta),
                y: center.y + radius * sin(theta)
            )
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, points: [CGPoint], phase: CGFloat) {
        guard points.count > 1 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = outerRadius(in: size)
        // Pocket / bore outline.
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2)),
            with: .color(.secondary.opacity(0.4)),
            lineWidth: 1
        )
        // Spiral, fading in as it goes — lighter (shallow) to solid (deep),
        // regardless of which way the radius itself is moving.
        for i in 0..<(points.count - 1) {
            let t = Double(i) / Double(points.count)
            var segment = Path()
            segment.move(to: points[i])
            segment.addLine(to: points[i + 1])
            context.stroke(segment, with: .color(.accentColor.opacity(0.35 + 0.65 * t)), lineWidth: 2)
        }
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
            with: .color(.secondary)
        )
        // Arrow at the very start of the spiral, showing entry direction.
        if points.count > 2 {
            let start = points[0]
            let startDirection = CGVector(dx: points[2].x - points[0].x, dy: points[2].y - points[0].y)
            context.fill(
                arrowhead(at: start, direction: CGVector(dx: -startDirection.dx, dy: -startDirection.dy)),
                with: .color(.accentColor.opacity(0.6))
            )
        }
        // Animated tool position.
        let dot = point(along: points, phase: phase)
        context.fill(
            Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
            with: .color(.accentColor)
        )
    }
}
