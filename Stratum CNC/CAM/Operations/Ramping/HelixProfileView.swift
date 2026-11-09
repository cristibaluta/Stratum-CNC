//
//  HelixProfileView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

struct HelixProfileView: View {
    let angle: Double
    /// Helix diameter, mm. Derived from the tool diameter (see `RampMath.helixDiameter`).
    let length: Double
    let stepdown: Double
    var direction: HelixDirection = .outsideIn
    private let cycleDuration: Double = 3.0

    /// The drawn spiral has a fixed width; `length` only drives the turn count.
    private let widthFraction: CGFloat = 0.85

    /// How the inner radius relates to the outer radius — kept identical to
    /// `HelixTopView` so the two views describe the same physical motion.
    private let innerRadiusFraction: CGFloat = 0.55

    /// Turns are capped for readability. If the real angle/diameter/stepdown
    /// combination would need more turns than this to reach the stepdown,
    /// we treat it the same way `LinearRampProfileView` treats "ramp length
    /// too short": draw what fits, in orange, and don't claim to reach it.
    private let maxDrawnTurns: Double = 8

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = makeLayout(in: size)

            TimelineView(.animation) { timeline in
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
        let surfaceY: CGFloat
        let stepdownY: CGFloat
        let reachesStepdown: Bool
        let turnsNeeded: Double
        let leftX: CGFloat
        let rightX: CGFloat
    }

    /// Pixel radius of the circular sweep (fixed, independent of the settings).
    private func motionRadius(availableWidth: CGFloat) -> CGFloat {
        availableWidth / 2 * widthFraction
    }

    private func makeLayout(in size: CGSize) -> Layout {
        let marginX = size.width * 0.08
        let topMargin = size.height * 0.14
        let bottomMargin = size.height * 0.22 // room for the diameter dimension label

        let availableWidth = size.width - marginX * 2
        let availableHeight = size.height - topMargin - bottomMargin

        let center = size.width / 2
        let outerRadiusPx = motionRadius(availableWidth: availableWidth)
        let innerRadiusPx = outerRadiusPx * innerRadiusFraction

        // --- Real-world (mm) depth-per-turn, independent of pixel scale ---
        let depthPerTurnMM = RampMath.helixDepthPerTurn(angle: angle, diameter: length)
        let turnsNeeded = RampMath.helixTurnsNeeded(angle: angle, diameter: length, stepdown: stepdown)
        let reachesStepdown = turnsNeeded <= maxDrawnTurns
        let drawnTurns = min(turnsNeeded, maxDrawnTurns)

        // How much depth the drawn portion actually covers, in mm — this is
        // what the canvas height maps to. When we reach stepdown this is
        // just `stepdown`; when we don't, it's however far `maxDrawnTurns`
        // gets us, so the drawn spiral still fills the available height.
        let physicalDepthDrawnMM = reachesStepdown ? stepdown : drawnTurns * depthPerTurnMM
        let depthScale = availableHeight / CGFloat(max(physicalDepthDrawnMM, 0.01))

        let pointsPerTurn = 48
        let totalPoints = max(Int(drawnTurns * Double(pointsPerTurn)), pointsPerTurn)

        let startRadius = direction == .outsideIn ? outerRadiusPx : innerRadiusPx
        let endRadius = direction == .outsideIn ? innerRadiusPx : outerRadiusPx

        let surfaceY = topMargin

        var points: [CGPoint] = []
        points.reserveCapacity(totalPoints + 1)
        for i in 0...totalPoints {
            let t = CGFloat(i) / CGFloat(totalPoints)
            let radius = startRadius + (endRadius - startRadius) * t
            let theta = t * CGFloat(drawnTurns) * 2 * .pi
            let x = center + radius * cos(theta)
            let depthMM = Double(t) * drawnTurns * depthPerTurnMM
            let y = surfaceY + CGFloat(depthMM) * depthScale
            points.append(CGPoint(x: x, y: y))
        }

        // Target stepdown line, projected with the same scale as the drawn
        // portion — on-canvas when we reach it, and clamped to the bottom
        // edge when we don't (the real target lies further down than what
        // we chose to draw).
        let rawStepdownY = surfaceY + CGFloat(stepdown) * depthScale
        let stepdownY = min(rawStepdownY, surfaceY + availableHeight)

        return Layout(
            points: points,
            surfaceY: surfaceY,
            stepdownY: stepdownY,
            reachesStepdown: reachesStepdown,
            turnsNeeded: turnsNeeded,
            leftX: center - outerRadiusPx,
            rightX: center + outerRadiusPx
        )
    }

    private func draw(context: inout GraphicsContext,
                      size: CGSize,
                      layout: Layout,
                      phase: CGFloat) {

        guard layout.points.count > 1 else {
            return
        }

        let surfaceY = layout.surfaceY
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

        // Maximum allowed stepdown.
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: 0, y: layout.stepdownY))
                p.addLine(to: CGPoint(x: size.width, y: layout.stepdownY))
            },
            with: .color(.secondary.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
        )

        // Diameter guides — the two extremes the circular motion sweeps
        // between, shown edge-on.
        for x in [layout.leftX, layout.rightX] {
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: x, y: surfaceY))
                    p.addLine(to: CGPoint(x: x, y: layout.stepdownY))
                },
                with: .color(.secondary.opacity(0.25)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 3])
            )
        }

        // Helix path, fading in as it goes deeper (shallow → solid), same
        // language as HelixTopView.
        let points = layout.points
        for i in 0..<(points.count - 1) {
            let t = Double(i) / Double(points.count)
            var segment = Path()
            segment.move(to: points[i])
            segment.addLine(to: points[i + 1])
            context.stroke(
                segment,
                with: .color(rampColor.opacity(0.35 + 0.65 * t)),
                lineWidth: 2
            )
        }

        // Entry marker.
        if let start = points.first {
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
        }

        // Animated tool position.
        let dot = point(along: points, phase: phase)
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

        // Calculated number of turns needed to reach the stepdown.
        let turnsText = String(format: "%.1f", layout.turnsNeeded)
        let label = "\(turnsText) turn\(turnsText == "1.0" ? "" : "s") to reach stepdown"
        let text = Text(label)
            .font(.caption.monospacedDigit())
            .foregroundColor(layout.reachesStepdown ? .secondary : .orange)

        context.draw(
            context.resolve(text),
            at: CGPoint(x: size.width / 2, y: size.height - 16),
            anchor: .center
        )
    }
}
