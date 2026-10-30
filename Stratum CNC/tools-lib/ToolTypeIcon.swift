//
//  ToolTypeIcon.swift
//  Stratum CNC
//
//  Small schematic icon showing only the tip profile of a tool type,
//  so tools can be told apart at a glance in the list. No dimensions.
//

import SwiftUI

struct ToolTypeIcon: View {

    let type: ToolType
    var size: CGFloat = 26

    var body: some View {
        Canvas { context, size in
            let path = Self.outline(for: type, in: size)
            context.fill(path, with: .color(.secondary.opacity(0.25)))
            context.stroke(
                path,
                with: .color(.primary.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)
            )

            // Extra detail lines that make some tips recognisable.
            if let detail = Self.detail(for: type, in: size) {
                context.stroke(
                    detail,
                    with: .color(.primary.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(type.displayName)
    }
}

private extension ToolTypeIcon {

    /// Outline drawn in a unit square (0...1) with the tip at the bottom.
    static func outline(for type: ToolType, in size: CGSize) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * size.width, y: y * size.height)
        }
        var p = Path()

        switch type {
        case .endMill:
            // Straight cutter with a flat end (the flutes are drawn as detail).
            p.addRect(CGRect(x: 0.3 * size.width, y: 0.08 * size.height,
                             width: 0.4 * size.width, height: 0.84 * size.height))

        case .ballNose:
            // Straight cutter ending in a hemisphere.
            p.move(to: pt(0.3, 0.08))
            p.addLine(to: pt(0.3, 0.6))
            p.addArc(center: pt(0.5, 0.6), radius: 0.2 * size.width,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            p.addLine(to: pt(0.7, 0.08))
            p.closeSubpath()

        case .drill:
            // Shank with a short pointed tip (half the point height it had, so it reads as a
            // drill without turning into a needle at small sizes).
            p.move(to: pt(0.3, 0.08))
            p.addLine(to: pt(0.3, 0.77))
            p.addLine(to: pt(0.5, 0.94))
            p.addLine(to: pt(0.7, 0.77))
            p.addLine(to: pt(0.7, 0.08))
            p.closeSubpath()

        case .engraving:
            // Thin body narrowing to a fine point.
            p.move(to: pt(0.38, 0.08))
            p.addLine(to: pt(0.38, 0.5))
            p.addLine(to: pt(0.5, 0.96))
            p.addLine(to: pt(0.62, 0.5))
            p.addLine(to: pt(0.62, 0.08))
            p.closeSubpath()

        case .vBit:
            // Narrow shank flaring into a wide V head.
            p.move(to: pt(0.4, 0.08))
            p.addLine(to: pt(0.4, 0.34))
            p.addLine(to: pt(0.12, 0.44))
            p.addLine(to: pt(0.5, 0.94))
            p.addLine(to: pt(0.88, 0.44))
            p.addLine(to: pt(0.6, 0.34))
            p.addLine(to: pt(0.6, 0.08))
            p.closeSubpath()

        case .chamfer:
            // Cone with a flat tip.
            p.move(to: pt(0.3, 0.08))
            p.addLine(to: pt(0.3, 0.3))
            p.addLine(to: pt(0.42, 0.92))
            p.addLine(to: pt(0.58, 0.92))
            p.addLine(to: pt(0.7, 0.3))
            p.addLine(to: pt(0.7, 0.08))
            p.closeSubpath()

        case .corn:
            // Wide straight cutter (teeth drawn as detail).
            p.addRect(CGRect(x: 0.22 * size.width, y: 0.08 * size.height,
                             width: 0.56 * size.width, height: 0.84 * size.height))

        case .threadMill:
            // Narrow neck ending in a slightly wider toothed head (teeth drawn as detail).
            p.addRect(CGRect(x: 0.4 * size.width, y: 0.08 * size.height,
                             width: 0.2 * size.width, height: 0.4 * size.height))
            p.addRect(CGRect(x: 0.28 * size.width, y: 0.48 * size.height,
                             width: 0.44 * size.width, height: 0.44 * size.height))

        case .solderMaskRemover:
            // Thin stem ending in a wide flat pad.
            p.addRect(CGRect(x: 0.42 * size.width, y: 0.08 * size.height,
                             width: 0.16 * size.width, height: 0.5 * size.height))
            p.addRect(CGRect(x: 0.15 * size.width, y: 0.58 * size.height,
                             width: 0.7 * size.width, height: 0.34 * size.height))
        }
        return p
    }

    static func detail(for type: ToolType, in size: CGSize) -> Path? {
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * size.width, y: y * size.height)
        }
        var p = Path()

        switch type {
        case .endMill:
            // Flutes: steep parallel lines across the body, cut off at its top and bottom.
            let left = 0.3, right = 0.7, top = 0.08, bottom = 0.92
            let slope = 0.85   // rise over run; the steeper, the more a helix
            for y0 in stride(from: 0.3, through: 1.1, by: 0.2) {
                var a = (x: left, y: y0)
                var b = (x: right, y: y0 - slope * (right - left))
                if a.y > bottom {
                    a = (x: left + (a.y - bottom) / slope, y: bottom)
                }
                if b.y < top {
                    b = (x: left + (y0 - top) / slope, y: top)
                }
                guard a.x < b.x else { continue }
                p.move(to: pt(a.x, a.y))
                p.addLine(to: pt(b.x, b.y))
            }
        case .corn:
            // Rows of teeth.
            for y in stride(from: 0.28, through: 0.8, by: 0.18) {
                p.move(to: pt(0.22, y))
                p.addLine(to: pt(0.78, y))
            }
            p.move(to: pt(0.5, 0.08))
            p.addLine(to: pt(0.5, 0.92))
        case .threadMill:
            // Thread teeth across the head.
            for y in stride(from: 0.56, through: 0.88, by: 0.1) {
                p.move(to: pt(0.28, y))
                p.addLine(to: pt(0.72, y))
            }
        case .drill:
            // Flute hint.
            p.move(to: pt(0.3, 0.3))
            p.addLine(to: pt(0.7, 0.42))
        default:
            return nil
        }
        return p
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(ToolType.allCases, id: \.self) { type in
            VStack {
                ToolTypeIcon(type: type)
                Text(type.displayName).font(.caption2)
            }
        }
    }
    .padding()
}
