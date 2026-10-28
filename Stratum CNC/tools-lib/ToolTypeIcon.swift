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
        .frame(width: 26, height: 26)
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
            // Straight cutter with a flat end.
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
            // Shank with a pointed (~118°) tip.
            p.move(to: pt(0.3, 0.08))
            p.addLine(to: pt(0.3, 0.6))
            p.addLine(to: pt(0.5, 0.94))
            p.addLine(to: pt(0.7, 0.6))
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
            // Narrow neck ending in a head with thread teeth on both sides.
            p = ThreadMillShape().path(in: CGRect(origin: .zero, size: size))

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
        case .corn:
            // Rows of teeth.
            for y in stride(from: 0.28, through: 0.8, by: 0.18) {
                p.move(to: pt(0.22, y))
                p.addLine(to: pt(0.78, y))
            }
            p.move(to: pt(0.5, 0.08))
            p.addLine(to: pt(0.5, 0.92))
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
