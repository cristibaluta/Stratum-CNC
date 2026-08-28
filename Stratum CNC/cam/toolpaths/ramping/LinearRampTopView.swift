//
//  LinearRampTopView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

struct LinearRampTopView: View {
    let angle: Double
    let length: Double
    let stepdown: Double
    private let cycleDuration: Double = 2.2

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let result = RampMath.linearRampOutcome(angle: angle, length: length, stepdown: stepdown)
            TimelineView(.animation) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)
                Canvas { context, _ in
                    draw(context: &context, size: size, result: result, phase: currentPhase)
                }
            }
        }
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        result: (usedLength: Double, depth: Double, reachesStepdown: Bool),
        phase: CGFloat
    ) {
        let inset = min(size.width, size.height) * 0.14
        let surfaceY = size.height * 0.50
        let startX = inset
        let availableWidth = size.width - inset * 2
        let rampFraction = min(max(result.usedLength / max(length, 0.1), 0.18), 1.0)
        let endX = startX + availableWidth * rampFraction
        // Stock/pocket footprint, viewed from above.
        let stock = CGRect(x: inset, y: size.height * 0.23, width: size.width - inset * 2, height: size.height * 0.54)
        context.stroke(Path(roundedRect: stock, cornerRadius: 7), with: .color(.secondary.opacity(0.45)), lineWidth: 1)
        // A linear ramp is a straight XY travel line from the entry point.
        let start = CGPoint(x: startX, y: surfaceY)
        let end = CGPoint(x: endX, y: surfaceY)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(result.reachesStepdown ? .accentColor : .orange), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        context.fill(arrowhead(at: end, direction: CGVector(dx: 1, dy: 0), length: 8, width: 6), with: .color(result.reachesStepdown ? .accentColor : .orange))
        // Tool position is animated along the XY entry path.
        let toolX = start.x + (end.x - start.x) * phase
        context.fill(Path(ellipseIn: CGRect(x: toolX - 4, y: surfaceY - 4, width: 8, height: 8)), with: .color(.primary))
        // Subtle depth cue: deeper ramps are represented by a progressively darker tail.
        context.fill(Path(ellipseIn: CGRect(x: start.x - 2, y: surfaceY - 2, width: 4, height: 4)), with: .color(.secondary))
    }
}
