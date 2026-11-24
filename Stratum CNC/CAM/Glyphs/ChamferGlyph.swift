//
//  ChamferGlyph.swift
//  Stratum CNC
//
//  The chamfer's own drawing: a side view of the edge, a horizontal line that turns down
//  through a 45° corner and continues as a vertical line. Used by `OperationIcon`.
//

import SwiftUI

/// Side view of a chamfered edge, drawn in the unit square. Stroke it; it follows whatever
/// foreground style it is given.
struct ChamferGlyph: Shape {

    func path(in rect: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var p = Path()
        p.move(to: pt(0.16, 0.16))
        p.addLine(to: pt(0.5, 0.16))     // horizontal
        p.addLine(to: pt(0.84, 0.5))     // 45° corner
        p.addLine(to: pt(0.84, 0.84))    // vertical
        return p
    }
}

#Preview {
    HStack(spacing: 20) {
        ChamferGlyph().stroke(lineWidth: 1.5).frame(width: 64, height: 64)
        OperationIcon(kind: .chamfer, size: 16)
    }
    .padding()
}
