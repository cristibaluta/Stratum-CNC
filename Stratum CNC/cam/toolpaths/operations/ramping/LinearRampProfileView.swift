//
//  LinearRampProfileView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

/// Side profile of a linear ramp.
struct LinearRampProfileView: View {
    let angle: Double
    let length: Double
    let stepdown: Double
    private let cycleDuration: Double = 2.8

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = makeLayout(in: size)

            TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)

                Canvas { context, _ in
                    draw(context: &context,
                         size: size,
                         layout: layout,
                         phase: currentPhase)
                }
            }
        }
    }

    private struct Layout {
        /// start (z0) → turnaround (half distance, half depth) → end (start x, full depth)
        let points: [CGPoint]
        let stepdownY: CGFloat
        let halfDistance: Double
        let reachesStepdown: Bool
    }

    private func makeLayout(in size: CGSize) -> Layout {
        let marginX = size.width * 0.08
        let topMargin = size.height * 0.14
        let bottomMargin = size.height * 0.10

        let availableWidth = size.width - marginX * 2
        let availableHeight = size.height - topMargin - bottomMargin

        let result = RampMath.linearRampOutcome(angle: angle,
                                                length: length,
                                                stepdown: stepdown)

        // The tool only travels half of the ramp distance away from the start.
        let halfDistance = result.usedLength / 2
        let halfDepth = result.depth / 2
        let fullDepth = result.depth

        // One pixels-per-mm factor for both axes keeps the drawn slope equal
        // to the real angle. Fit to the width, or to the height when steep.
        let tallest = max(fullDepth, stepdown, 0.01)
        let k = min(
            availableWidth / CGFloat(max(halfDistance, 0.01)),
            availableHeight / CGFloat(tallest)
        )

        let rampWidth = CGFloat(halfDistance) * k
        let startX = (size.width - rampWidth) / 2
        let surfaceY = topMargin

        let start = CGPoint(x: startX, y: surfaceY)
        let turn = CGPoint(x: startX + rampWidth, y: surfaceY + CGFloat(halfDepth) * k)
        let end = CGPoint(x: startX, y: surfaceY + CGFloat(fullDepth) * k)

        return Layout(points: [start, turn, end],
                      stepdownY: surfaceY + CGFloat(stepdown) * k,
                      halfDistance: halfDistance,
                      reachesStepdown: result.reachesStepdown)
    }

    private func draw(context: inout GraphicsContext,
                      size: CGSize,
                      layout: Layout,
                      phase: CGFloat) {

        let points = layout.points
        guard points.count == 3 else {
            return
        }

        let start = points[0]
        let turn = points[1]
        let end = points[2]

        let surfaceY = start.y
        let rampColor: Color = layout.reachesStepdown ? .accentColor : .orange

        // Material below the stock surface.
        var material = Path()
        material.move(to: CGPoint(x: 0, y: surfaceY))
        material.addLine(to: CGPoint(x: size.width, y: surfaceY))
        material.addLine(to: CGPoint(x: size.width, y: size.height))
        material.addLine(to: CGPoint(x: 0, y: size.height))
        material.closeSubpath()

        context.fill(material, with: .color(.brown.opacity(0.18)))

        // Stock surface.
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: 0, y: surfaceY))
                p.addLine(to: CGPoint(x: size.width, y: surfaceY))
            },
            with: .color(.secondary),
            lineWidth: 1
        )

        // Stepdown level.
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: 0, y: layout.stepdownY))
                p.addLine(to: CGPoint(x: size.width, y: layout.stepdownY))
            },
            with: .color(.secondary.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
        )

        // Leg 1: z0 → half distance, half of the stepdown.
        context.stroke(
            Path { p in
                p.move(to: start)
                p.addLine(to: turn)
            },
            with: .color(rampColor),
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )

        // Leg 2: back to the start point, finishing at the stepdown z.
        context.stroke(
            Path { p in
                p.move(to: turn)
                p.addLine(to: end)
            },
            with: .color(rampColor.opacity(0.6)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 4])
        )

        context.fill(
            arrowhead(
                at: end,
                direction: CGVector(dx: end.x - turn.x, dy: end.y - turn.y)
            ),
            with: .color(rampColor.opacity(0.8))
        )

        // Entry marker.
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: start.x - 3,
                    y: start.y - 3,
                    width: 6,
                    height: 6
                )
            ),
            with: .color(.secondary)
        )

        // Animated tool position.
        let dot = point(
            along: points,
            phase: phase
        )

        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: dot.x - 5,
                    y: dot.y - 5,
                    width: 10,
                    height: 10
                )
            ),
            with: .color(rampColor)
        )

        // Horizontal extent of the ramp (half of the full ramp distance).
        let dimensionY = min(
            max(turn.y, end.y) + 28,
            size.height - 14
        )

        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: start.x, y: dimensionY))
                p.addLine(to: CGPoint(x: turn.x, y: dimensionY))

                // Left extension.
                p.move(to: CGPoint(x: start.x, y: end.y))
                p.addLine(to: CGPoint(x: start.x, y: dimensionY))

                // Right extension.
                p.move(to: CGPoint(x: turn.x, y: turn.y))
                p.addLine(to: CGPoint(x: turn.x, y: dimensionY))
            },
            with: .color(.secondary.opacity(0.7)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
        )

        context.fill(
            arrowhead(
                at: CGPoint(x: start.x, y: dimensionY),
                direction: CGVector(dx: -1, dy: 0),
                length: 6,
                width: 4
            ),
            with: .color(.secondary.opacity(0.8))
        )

        context.fill(
            arrowhead(
                at: CGPoint(x: turn.x, y: dimensionY),
                direction: CGVector(dx: 1, dy: 0),
                length: 6,
                width: 4
            ),
            with: .color(.secondary.opacity(0.8))
        )

        let label = String(format: "%.2f mm", layout.halfDistance)
        let text = Text(label)
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)

        let resolvedText = context.resolve(text)
        let textSize = resolvedText.measure(in: CGSize(width: 120, height: 30))

        context.draw(
            resolvedText,
            at: CGPoint(
                x: (start.x + turn.x) / 2,
                y: dimensionY - textSize.height / 2 - 5
            ),
            anchor: .center
        )
    }
}
