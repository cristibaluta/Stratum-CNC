//
//  LinearRampProfileView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

struct LinearRampProfileView: View {
    let angle: Double
    let length: Double
    let stepdown: Double
    var returnMode: LinearRampReturnMode = .retrace
    private let cycleDuration: Double = 2.8

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = makeLayout(in: size)

            TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)

                Canvas { context, _ in
                    draw(
                        context: &context,
                        size: size,
                        layout: layout,
                        phase: currentPhase
                    )
                }
            }
        }
    }

    private struct Layout {
        let points: [CGPoint]
        let stepdownY: CGFloat
        let reachesStepdown: Bool
    }

    private func makeLayout(in size: CGSize) -> Layout {
        let marginX = size.width * 0.08
        let topMargin = size.height * 0.14
        let bottomMargin = size.height * 0.10

        let availableWidth = size.width - marginX * 2
        let availableHeight = size.height - topMargin - bottomMargin

        let result = RampMath.linearRampOutcome(
            angle: angle,
            length: length,
            stepdown: stepdown
        )

        let angleRadians = RampMath.clampedAngle(angle) * .pi / 180
        let slope = tan(angleRadians)

        // The ramp should occupy almost the entire width.
        let rampWidth = availableWidth

        // Calculate the depth that this horizontal distance would produce
        // at the real angle.
        let geometricDepth = rampWidth * slope

        // Scale the entire profile uniformly when the requested angle would
        // otherwise extend beyond the available vertical space.
        let scale = geometricDepth > availableHeight
            ? availableHeight / geometricDepth
            : 1.0

        let finalRampWidth = rampWidth * scale
        let finalDepth = geometricDepth * scale

        // Keep the ramp centered horizontally.
        let startX = (size.width - finalRampWidth) / 2
        let surfaceY = topMargin

        let rampEndX = startX + finalRampWidth
        let rampEndY = surfaceY + finalDepth

        // The visual ramp represents the requested physical angle.
        let rampEnd = CGPoint(
            x: rampEndX,
            y: rampEndY
        )

        let start = CGPoint(
            x: startX,
            y: surfaceY
        )

        let stageTwo: CGPoint

        if result.reachesStepdown {
            switch returnMode {
            case .advance:
                stageTwo = CGPoint(
                    x: size.width - marginX,
                    y: rampEndY
                )

            case .retrace:
                stageTwo = CGPoint(
                    x: startX,
                    y: rampEndY
                )
            }
        } else {
            stageTwo = rampEnd
        }

        // Stepdown line is positioned using the same vertical scale as
        // the ramp, so it remains geometrically consistent.
        let depthScale = finalDepth / max(result.depth, 0.01)

        let stepdownY = surfaceY + CGFloat(stepdown) * depthScale

        return Layout(
            points: [start, rampEnd, stageTwo],
            stepdownY: stepdownY,
            reachesStepdown: result.reachesStepdown
        )
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        layout: Layout,
        phase: CGFloat
    ) {
        let points = layout.points
        guard points.count == 3 else { return }

        let start = points[0]
        let rampEnd = points[1]
        let stageTwo = points[2]

        let surfaceY = start.y
        let rampColor: Color = layout.reachesStepdown ? .accentColor : .orange

        // Material below the stock surface.
        var material = Path()
        material.move(to: CGPoint(x: 0, y: surfaceY))
        material.addLine(to: CGPoint(x: size.width, y: surfaceY))
        material.addLine(to: CGPoint(x: size.width, y: size.height))
        material.addLine(to: CGPoint(x: 0, y: size.height))
        material.closeSubpath()

        context.fill(
            material,
            with: .color(.brown.opacity(0.18))
        )

        // Stock surface.
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: 0, y: surfaceY))
                p.addLine(to: CGPoint(x: size.width, y: surfaceY))
            },
            with: .color(.secondary),
            lineWidth: 1
        )

        // Maximum allowed stepdown.
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: 0, y: layout.stepdownY))
                p.addLine(to: CGPoint(x: size.width, y: layout.stepdownY))
            },
            with: .color(.secondary.opacity(0.5)),
            style: StrokeStyle(
                lineWidth: 1,
                dash: [3, 3]
            )
        )

        if layout.reachesStepdown {
            // Stage 2: movement at full depth.
            context.stroke(
                Path { p in
                    p.move(to: rampEnd)
                    p.addLine(to: stageTwo)
                },
                with: .color(.accentColor.opacity(0.45)),
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    dash: [5, 3]
                )
            )

            let direction = CGVector(
                dx: stageTwo.x - rampEnd.x,
                dy: stageTwo.y - rampEnd.y
            )

            if direction.dx != 0 || direction.dy != 0 {
                context.fill(
                    arrowhead(
                        at: stageTwo,
                        direction: direction
                    ),
                    with: .color(.accentColor.opacity(0.7))
                )
            }
        } else {
            // The available ramp length is insufficient to reach stepdown.
            // Show where the ramp would need to continue.
            let angleRadians = RampMath.clampedAngle(angle) * .pi / 180
            let remainingWidth = min(
                36,
                size.width * 0.15
            )

            let verticalScale = (
                layout.stepdownY - surfaceY
            ) / CGFloat(max(stepdown, 0.01))

            let horizontalScale = (
                rampEnd.x - start.x
            ) / CGFloat(max(length, 0.1))

            let ghostEnd = CGPoint(
                x: rampEnd.x + remainingWidth,
                y: rampEnd.y
                    + remainingWidth
                    * CGFloat(tan(angleRadians))
                    * (verticalScale / horizontalScale)
            )

            context.stroke(
                Path { p in
                    p.move(to: rampEnd)
                    p.addLine(to: ghostEnd)
                },
                with: .color(.orange.opacity(0.5)),
                style: StrokeStyle(
                    lineWidth: 1.5,
                    dash: [2, 3]
                )
            )
        }

        // Main ramp.
        context.stroke(
            Path { p in
                p.move(to: start)
                p.addLine(to: rampEnd)
            },
            with: .color(rampColor),
            style: StrokeStyle(
                lineWidth: 3,
                lineCap: .round
            )
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

        // Calculated horizontal ramp distance.
        let horizontalDistance = RampMath.linearRequiredLength(
            angle: angle,
            stepdown: stepdown
        )

        let dimensionY = min(
            rampEnd.y + 28,
            size.height - 14
        )

        // Dimension line.
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: start.x, y: dimensionY))
                p.addLine(to: CGPoint(x: rampEnd.x, y: dimensionY))

                // Left extension.
                p.move(to: CGPoint(x: start.x, y: rampEnd.y))
                p.addLine(to: CGPoint(x: start.x, y: dimensionY))

                // Right extension.
                p.move(to: CGPoint(x: rampEnd.x, y: rampEnd.y))
                p.addLine(to: CGPoint(x: rampEnd.x, y: dimensionY))
            },
            with: .color(.secondary.opacity(0.7)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
        )

        // Dimension arrows.
        context.fill(
            arrowhead(
                at: CGPoint(x: start.x, y: dimensionY),
                direction: CGVector(dx: 1, dy: 0),
                length: 6,
                width: 4
            ),
            with: .color(.secondary.opacity(0.8))
        )

        context.fill(
            arrowhead(
                at: CGPoint(x: rampEnd.x, y: dimensionY),
                direction: CGVector(dx: -1, dy: 0),
                length: 6,
                width: 4
            ),
            with: .color(.secondary.opacity(0.8))
        )

        // Distance label.
        let label = String(format: "%.2f mm", horizontalDistance)
        let text = Text(label)
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)

        let resolvedText = context.resolve(text)
        let textSize = resolvedText.measure(in: CGSize(width: 120, height: 30))

        context.draw(
            resolvedText,
            at: CGPoint(
                x: (start.x + rampEnd.x) / 2,
                y: dimensionY - textSize.height / 2 - 5
            ),
            anchor: .center
        )

        // Animated tool position.
        let dot2 = point(
            along: points,
            phase: phase
        )

        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: dot2.x - 5,
                    y: dot2.y - 5,
                    width: 10,
                    height: 10
                )
            ),
            with: .color(rampColor)
        )
    }
}
