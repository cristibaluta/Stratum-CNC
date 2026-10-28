//
//  ContourTypeGlyph.swift
//  Stratum CNC
//
//  Custom drawing, moved out of ContourPicker.swift.
//

import SwiftUI
import StratumCAM

/// A small plan view: the selected shape (solid outline, lightly shaded), the tool's path
/// (dashed) and the tool itself (circle with its centre marked) sitting on that path.
/// The path is offset from the shape by exactly the tool's radius, so the picture shows why:
/// inside keeps the tool's body within the shape, outside keeps it clear of it, and on
/// contour puts the tool's centre right on the line.
/// Drawn in a fixed 48x32 design space and scaled to whatever frame it's given.
struct ContourTypeGlyph: View {
    let position: SC.CutSide
    var tint: Color = .primary

    private let designSize = CGSize(width: 48, height: 32)
    private let toolRadius: CGFloat = 3.5
    private let shape = CGRect(x: 10, y: 9, width: 28, height: 16)
    private let shapeCorner: CGFloat = 2.5

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / designSize.width, size.height / designSize.height)
            context.translateBy(x: (size.width - designSize.width * scale) / 2,
                                y: (size.height - designSize.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)

            let line = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)

            // The selected shape.
            let shapePath = Path(roundedRect: shape, cornerRadius: shapeCorner)
            context.fill(shapePath, with: .color(Color.secondary.opacity(0.12)))
            context.stroke(shapePath, with: .color(Color.secondary.opacity(0.65)), style: line)

            // The tool's path, offset from the shape by the tool's radius.
            let pathRect = shape.insetBy(dx: pathOffset, dy: pathOffset)
            context.stroke(Path(roundedRect: pathRect, cornerRadius: pathCornerRadius),
                           with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2.5, 2]))

            // The tool, centred on its path, with its centre marked.
            let center = CGPoint(x: shape.midX, y: pathRect.minY)
            let toolRect = CGRect(x: center.x - toolRadius, y: center.y - toolRadius,
                                  width: toolRadius * 2, height: toolRadius * 2)
            context.fill(Path(ellipseIn: toolRect), with: .color(tint.opacity(0.18)))
            context.stroke(Path(ellipseIn: toolRect), with: .color(tint), style: line)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2)),
                         with: .color(tint))
        }
    }

    /// Positive pulls the path in from the shape (inside), negative pushes it out past the
    /// shape (outside); zero traces the shape itself (on the line).
    private var pathOffset: CGFloat {
        switch position {
            case .onContour: return 0
            case .inside:    return toolRadius
            case .outside:   return -toolRadius
        }
    }

    private var pathCornerRadius: CGFloat {
        switch position {
            case .onContour: return shapeCorner
            case .inside:    return 1
            case .outside:   return shapeCorner + toolRadius
        }
    }
}
