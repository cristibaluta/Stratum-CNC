//
//  ZigZagTopView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

struct ZigZagTopView: View {
    let angle: Double
    let length: Double
    private let cycleDuration: Double = 2.6
    /// Reference ramp length (mm) that fills the full available width.
    /// Shorter ramps occupy proportionally less of the channel.
    private let referenceLength: Double = 30
    private let minWidthFraction: CGFloat = 0.3

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = zigZagPoints(in: size)
            TimelineView(.animation) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)
                Canvas { context, _ in
                    draw(context: &context, size: size, points: points, phase: currentPhase)
                }
            }
        }
    }

    private func zigZagPoints(in size: CGSize) -> [CGPoint] {
        let marginX = size.width * 0.1
        let top = size.height * 0.3
        let bottom = size.height * 0.7
        let toothCount = RampMath.zigZagPasses(angle: angle, length: length)
        // The pattern's footprint reflects `length` — a short ramp visibly
        // uses only part of the channel instead of always filling the canvas.
        let widthFraction = min(max(CGFloat(length / referenceLength), minWidthFraction), 1.0)
        let usableWidth = size.width - marginX * 2
        let patternWidth = usableWidth * widthFraction
        let startX = marginX + (usableWidth - patternWidth) / 2
        let stepX = patternWidth / CGFloat(toothCount)
        var points: [CGPoint] = []
        var isTop = true
        for i in 0...toothCount {
            let x = startX + stepX * CGFloat(i)
            let y = isTop ? top : bottom
            points.append(CGPoint(x: x, y: y))
            isTop.toggle()
        }
        return points
    }

    private func draw(context: inout GraphicsContext, size: CGSize, points: [CGPoint], phase: CGFloat) {
        guard points.count > 1 else { return }
        let top = points.map(\.y).min() ?? 0
        let bottom = points.map(\.y).max() ?? size.height
        // Channel / slot walls span the full width, showing the zig-zag
        // pattern only occupies part of it when the ramp length is short.
        for y in [top, bottom] {
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                },
                with: .color(.secondary.opacity(0.3)),
                lineWidth: 1
            )
        }
        // The zig-zag tool path, fading darker with each pass to show
        // progressive depth — same convention as the helix view.
        for i in 0..<(points.count - 1) {
            let t = Double(i) / Double(points.count - 1)
            var segment = Path()
            segment.move(to: points[i])
            segment.addLine(to: points[i + 1])
            context.stroke(
                segment,
                with: .color(.accentColor.opacity(0.35 + 0.65 * t)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        // Arrowheads at each direction change, so the back-and-forth motion reads clearly.
        for i in 1..<(points.count - 1) {
            let incoming = CGVector(dx: points[i].x - points[i - 1].x, dy: points[i].y - points[i - 1].y)
            context.fill(
                arrowhead(at: points[i], direction: incoming, length: 6, width: 4),
                with: .color(.accentColor.opacity(0.8))
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
