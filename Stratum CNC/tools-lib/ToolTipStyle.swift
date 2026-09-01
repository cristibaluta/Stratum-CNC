//
//  ToolTipStyle.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 27.08.2026.
//


//
//  ToolDiagramView.swift
//  Stratum CNC
//
//  Draws a schematic side-view of a cutting tool (shank + flute + tip)
//  with DS / LS / LC / DC dimension callouts, similar to the reference
//  "Tool Information" panel.
//
//  This view is intentionally decoupled from `Tool` / `ToolType` — it only
//  needs plain numbers + a tip style — so it can be dropped in next to your
//  existing model types without any naming collisions. Map your own
//  `ToolType` to a `ToolTipStyle` at the call site (see the extension at the
//  bottom of ToolEditorView.swift).
//

import SwiftUI

/// How the bottom of the tool is shaped.
enum ToolTipStyle {
    case flat                              // flat end mill
    case ball                              // ball nose
    case conical(angleDegrees: Double)     // drill / v-bit, included angle
}

/// Schematic drawing of a tool: shank on top, flute below, shaped tip at
/// the bottom, with dimension arrows for shank diameter (DS), shoulder
/// length (LS), flute/cut length (LC) and tool diameter (DC).
struct ToolDiagramView: View {

    var shankDiameter: Double        // DS, mm
    var toolDiameter: Double         // DC, mm
    var shoulderLength: Double       // LS, mm — visible shank length above the flute
    var fluteLength: Double          // LC, mm — cutting length
    var tipStyle: ToolTipStyle = .flat

    // Visual tuning — purely cosmetic, doesn't need to be physically accurate.
    private let horizontalInset: CGFloat = 40   // room for DS / DC arrows + labels
    private let topInset: CGFloat = 32          // room for the DS label row
    private let bottomInset: CGFloat = 32       // room for the DC label row
    private let fluteColor = Color(white: 0.72)
    private let shankColor = Color(white: 0.86)
    private let outlineColor = Color(white: 0.35)
    private let dimensionColor = Color(white: 0.25)

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        // --- Layout math -----------------------------------------------
        let drawableHeight = size.height - topInset - bottomInset
        let maxDiameter = max(shankDiameter, toolDiameter, 0.001)
        // Reserve a slice of vertical space proportional to shoulder vs
        // flute length so the picture roughly reflects the ratio, but keep
        // sane minimums so short tools are still legible.
        let totalLength = max(shoulderLength + fluteLength, 0.001)
        let shoulderFraction = max(min(shoulderLength / totalLength, 0.85), 0.15)

        let shankHeight = drawableHeight * shoulderFraction
        let fluteHeight = drawableHeight * (1 - shoulderFraction)

        let centerX = size.width / 2
        let maxHalfWidth = (size.width - horizontalInset * 2) / 2

        func halfWidth(for diameter: Double) -> CGFloat {
            CGFloat(diameter / maxDiameter) * maxHalfWidth
        }

        let shankHalf = halfWidth(for: shankDiameter)
        let fluteHalf = halfWidth(for: toolDiameter)

        let shankTopY = topInset
        let shankBottomY = topInset + shankHeight
        let fluteTopY = shankBottomY
        let tipBaseY = fluteTopY + fluteHeight

        // --- Shank -------------------------------------------------------
        var shankPath = Path()
        shankPath.addRect(CGRect(
            x: centerX - shankHalf,
            y: shankTopY,
            width: shankHalf * 2,
            height: shankHeight
        ))
        context.fill(shankPath, with: .color(shankColor))
        context.stroke(shankPath, with: .color(outlineColor), lineWidth: 1.2)

        // --- Flute (tapered shoulder if diameters differ; full width for conical tips) ---
        let fluteBodyHalf: CGFloat = {
            if case .conical = tipStyle {
                return shankHalf   // engraving/chamfer bits: body stays shank width, only the tip narrows
            } else {
                return fluteHalf
            }
        }()

        // Pre-compute how far the cone eats into the flute length, so the
        // cylindrical body stops before it and the apex still lands on tipBaseY.
        var fluteBottomY = tipBaseY
        if case .conical(let angleDegrees) = tipStyle {
            let halfAngle = max(min(angleDegrees, 179), 1) / 2
            let tipDrop = fluteBodyHalf / CGFloat(tan(halfAngle * .pi / 180))
            fluteBottomY = max(tipBaseY - tipDrop, fluteTopY + 6)
        }

        var flutePath = Path()
        flutePath.move(to: CGPoint(x: centerX - shankHalf, y: fluteTopY))
        flutePath.addLine(to: CGPoint(x: centerX - fluteBodyHalf, y: fluteTopY + 6))
        flutePath.addLine(to: CGPoint(x: centerX - fluteBodyHalf, y: fluteBottomY))
        flutePath.addLine(to: CGPoint(x: centerX + fluteBodyHalf, y: fluteBottomY))
        flutePath.addLine(to: CGPoint(x: centerX + fluteBodyHalf, y: fluteTopY + 6))
        flutePath.addLine(to: CGPoint(x: centerX + shankHalf, y: fluteTopY))
        flutePath.closeSubpath()
        context.fill(flutePath, with: .color(fluteColor))

        // Flute helix hint — a few diagonal stroke pairs for texture.
        let fluteStripeCount = 5
        if tipBaseY > fluteTopY + 6 {
            for i in 0..<fluteStripeCount {
                let t = CGFloat(i) / CGFloat(fluteStripeCount)
                let y0 = fluteTopY + 6 + t * (tipBaseY - fluteTopY - 6)
                var stripe = Path()
                stripe.move(to: CGPoint(x: centerX - fluteBodyHalf, y: y0))
                stripe.addLine(to: CGPoint(x: centerX + fluteBodyHalf, y: y0 + 8))
                context.stroke(stripe, with: .color(outlineColor.opacity(0.35)), lineWidth: 0.75)
            }
        }
        context.stroke(flutePath, with: .color(outlineColor), lineWidth: 1.2)

        // --- Tip ----------------------------------------------------------
        var tipPath = Path()
        switch tipStyle {
            case .flat:
                tipPath.addRect(CGRect(
                    x: centerX - fluteHalf, y: tipBaseY - 1,
                    width: fluteHalf * 2, height: 2
                ))
            case .ball:
                let r = fluteHalf
                tipPath.addArc(
                    center: CGPoint(x: centerX, y: tipBaseY),
                    radius: r,
                    startAngle: .degrees(0),
                    endAngle: .degrees(180),
                    clockwise: false
                )
            case .conical(let angleDegrees):
                let halfAngle = max(min(angleDegrees, 179), 1) / 2
                let tipDrop = fluteBodyHalf / CGFloat(tan(halfAngle * .pi / 180))
                // Carve the cone out of the tail end of the existing flute length,
                // instead of extending past it — apex lands on tipBaseY.
                let coneBaseY = max(tipBaseY - tipDrop, fluteTopY + 6)
                tipPath.move(to: CGPoint(x: centerX - fluteBodyHalf, y: coneBaseY))
                tipPath.addLine(to: CGPoint(x: centerX, y: tipBaseY))
                tipPath.addLine(to: CGPoint(x: centerX + fluteBodyHalf, y: coneBaseY))
                tipPath.closeSubpath()
        }
        context.fill(tipPath, with: .color(fluteColor))
        context.stroke(tipPath, with: .color(outlineColor), lineWidth: 1.2)

        // --- Dimension callouts -------------------------------------------
        drawDS(in: &context, centerX: centerX, shankHalf: shankHalf, topY: shankTopY)
        drawDC(in: &context, centerX: centerX, fluteHalf: fluteHalf, bottomY: bottomLineY(size: size))
//        drawVerticalBracket(
//            in: &context,
//            label: "LS",
//            x: centerX - maxHalfWidth - 22,
//            topY: shankBottomY,
//            bottomY: tipBaseY
//        )
        drawVerticalBracket(in: &context, label: "L", x: centerX + maxHalfWidth + 22, topY: fluteTopY, bottomY: tipBaseY)
    }

    private func bottomLineY(size: CGSize) -> CGFloat {
        size.height - bottomInset + 14
    }

    private func drawDS(in context: inout GraphicsContext, centerX: CGFloat, shankHalf: CGFloat, topY: CGFloat) {
        let y = topY - 14
        drawArrowRow(in: &context, y: y, leftX: centerX - shankHalf, rightX: centerX + shankHalf)
        drawLabel(in: &context, text: "DS", at: CGPoint(x: centerX, y: topY - 26))
    }

    private func drawDC(in context: inout GraphicsContext, centerX: CGFloat, fluteHalf: CGFloat, bottomY: CGFloat) {
        drawArrowRow(in: &context, y: bottomY, leftX: centerX - fluteHalf, rightX: centerX + fluteHalf)
        drawLabel(in: &context, text: "DC", at: CGPoint(x: centerX, y: bottomY + 14))
    }

    private func drawArrowRow(in context: inout GraphicsContext, y: CGFloat, leftX: CGFloat, rightX: CGFloat) {
        var line = Path()
        line.move(to: CGPoint(x: leftX, y: y))
        line.addLine(to: CGPoint(x: rightX, y: y))
        context.stroke(line, with: .color(dimensionColor), lineWidth: 1)
        drawArrowHead(in: &context, at: CGPoint(x: leftX, y: y), pointingRight: false)
        drawArrowHead(in: &context, at: CGPoint(x: rightX, y: y), pointingRight: true)
    }

    private func drawArrowHead(in context: inout GraphicsContext, at point: CGPoint, pointingRight: Bool) {
        let size: CGFloat = 5
        let dir: CGFloat = pointingRight ? 1 : -1
        var arrow = Path()
        arrow.move(to: point)
        arrow.addLine(to: CGPoint(x: point.x + dir * size, y: point.y - size * 0.6))
        arrow.move(to: point)
        arrow.addLine(to: CGPoint(x: point.x + dir * size, y: point.y + size * 0.6))
        context.stroke(arrow, with: .color(dimensionColor), lineWidth: 1)
    }

    private func drawVerticalBracket(in context: inout GraphicsContext, label: String, x: CGFloat, topY: CGFloat, bottomY: CGFloat) {
        guard bottomY - topY > 1 else { return }
        var line = Path()
        line.move(to: CGPoint(x: x, y: topY))
        line.addLine(to: CGPoint(x: x, y: bottomY))
        context.stroke(line, with: .color(dimensionColor), lineWidth: 1)
        drawArrowHead(rotated90: true, in: &context, at: CGPoint(x: x, y: topY), pointingDown: false)
        drawArrowHead(rotated90: true, in: &context, at: CGPoint(x: x, y: bottomY), pointingDown: true)

        context.draw(
            Text(label).font(.caption2.weight(.semibold)).foregroundColor(dimensionColor),
            at: CGPoint(x: x + 10, y: (topY + bottomY) / 2),
            anchor: .center
        )
    }

    private func drawArrowHead(rotated90 _: Bool, in context: inout GraphicsContext, at point: CGPoint, pointingDown: Bool) {
        let size: CGFloat = 5
        let dir: CGFloat = pointingDown ? 1 : -1
        var arrow = Path()
        arrow.move(to: point)
        arrow.addLine(to: CGPoint(x: point.x - size * 0.6, y: point.y + dir * size))
        arrow.move(to: point)
        arrow.addLine(to: CGPoint(x: point.x + size * 0.6, y: point.y + dir * size))
        context.stroke(arrow, with: .color(dimensionColor), lineWidth: 1)
    }

    private func drawLabel(in context: inout GraphicsContext, text: String, at point: CGPoint) {
        context.draw(
            Text(text).font(.caption2.weight(.semibold)).foregroundColor(dimensionColor),
            at: point,
            anchor: .center
        )
    }
}

// MARK: - Previews

#Preview("Drill") {
    ToolDiagramView(
        shankDiameter: 3.175,
        toolDiameter: 0.8,
        shoulderLength: 12,
        fluteLength: 10,
        tipStyle: .conical(angleDegrees: 118)
    )
    .padding()
    .frame(width: 260, height: 280)
}

#Preview("Ball Nose") {
    ToolDiagramView(
        shankDiameter: 3.175,
        toolDiameter: 3.175,
        shoulderLength: 8,
        fluteLength: 14,
        tipStyle: .ball
    )
    .padding()
    .frame(width: 260, height: 280)
}

#Preview("Flat End") {
    ToolDiagramView(
        shankDiameter: 6,
        toolDiameter: 6,
        shoulderLength: 6,
        fluteLength: 20,
        tipStyle: .flat
    )
    .padding()
    .frame(width: 260, height: 280)
}
