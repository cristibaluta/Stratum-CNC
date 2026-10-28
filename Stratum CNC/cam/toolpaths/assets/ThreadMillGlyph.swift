//
//  ThreadMillGlyph.swift
//  Stratum CNC
//
//  The thread mill's own drawing: a narrow neck ending in a head whose sides are cut into
//  thread teeth, flat at the bottom. Used for the Thread Mill tool type in the tool library
//  (`ToolTypeIcon`) and for the Thread mill operation (`OperationIcon`), so the two match.
//

import SwiftUI

/// Side view of a thread mill, drawn in the unit square with the tip at the bottom. Stroke it
/// for an outline icon or fill it; it follows whatever foreground style it is given.
struct ThreadMillShape: Shape {

    /// Teeth along each side of the head.
    private let teethCount = 4

    func path(in rect: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        let neckLeft = 0.4, neckRight = 0.6
        let root = 0.34, tip = 0.2           // head half-widths measured from the centre line
        let top = 0.06, headTop = 0.42, bottom = 0.94
        let toothHeight = (bottom - headTop - 0.04) / Double(teethCount)

        var p = Path()
        // Down the left side: neck, then the teeth.
        p.move(to: pt(neckLeft, top))
        p.addLine(to: pt(neckLeft, headTop))
        for i in 0..<teethCount {
            let y = headTop + toothHeight * Double(i)
            p.addLine(to: pt(0.5 - root, y))
            p.addLine(to: pt(0.5 - tip, y + toothHeight * 0.5))
            p.addLine(to: pt(0.5 - root, y + toothHeight))
        }
        // Flat end.
        let teethEnd = headTop + toothHeight * Double(teethCount)
        p.addLine(to: pt(0.5 - root, bottom))
        p.addLine(to: pt(0.5 + root, bottom))
        p.addLine(to: pt(0.5 + root, teethEnd))
        // Back up the right side.
        for i in (0..<teethCount).reversed() {
            let y = headTop + toothHeight * Double(i)
            p.addLine(to: pt(0.5 + tip, y + toothHeight * 0.5))
            p.addLine(to: pt(0.5 + root, y))
        }
        p.addLine(to: pt(neckRight, headTop))
        p.addLine(to: pt(neckRight, top))
        p.closeSubpath()
        return p
    }
}

/// The icon of an operation: its SF Symbol, or a drawing of its own where SF Symbols have
/// nothing fitting (the thread mill). Sized like `Image(systemName:).font(.system(size:))`;
/// colour it with `foregroundStyle`.
struct OperationIcon: View {
    let kind: OperationKind
    var size: CGFloat = 16

    var body: some View {
        if kind == .threadMilling {
            ThreadMillShape()
                .stroke(style: StrokeStyle(lineWidth: max(1, size / 13), lineJoin: .round))
                .frame(width: size, height: size)
        } else {
            Image(systemName: kind.symbol)
                .font(.system(size: size))
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        ThreadMillShape().stroke(lineWidth: 1.5).frame(width: 64, height: 64)
        OperationIcon(kind: .threadMilling, size: 16)
        OperationIcon(kind: .drilling, size: 16)
    }
    .padding()
}
