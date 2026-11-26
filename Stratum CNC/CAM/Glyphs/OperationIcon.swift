//
//  OperationIcon.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 11.11.2026.
//

import SwiftUI
import StratumCAM

/// The icon of an operation, shared by the toolpath rows, the toolpath details and the pickers.
/// The area an operation mills is filled (a pocket is a filled square, a drill a filled circle,
/// a slot a filled low capsule); one that only follows a line is an outline (contour, bore). The
/// thread mill, the chamfer, the engrave and the rest operation keep a drawing or SF Symbol of
/// their own. Sized like `Image(systemName:).font(.system(size:))`; colour it with `foregroundStyle`.
struct OperationIcon: View {
    let kind: SC.MachiningOperation.Kind
    /// A rest operation has the icon of its own, not of the pocket it is made from.
    var isRest: Bool = false
    var size: CGFloat = 16

    var body: some View {
        // The shapes are a little smaller than the box, as SF Symbols are
        let side = size * 0.8
        let line = max(1, side / 8)
        Group {
            if isRest {
                Image(systemName: "angle")
                    .font(.system(size: size))
            } else {
                switch kind {
                    case .pocket, .pocket3D:
                        RoundedRectangle(cornerRadius: side / 8)
                            .frame(width: side, height: side)
                    case .facing:
                        Rectangle()
                            .frame(width: side, height: side * 0.6)
                    case .contour:
                        RoundedRectangle(cornerRadius: side / 8)
                            .inset(by: line / 2)
                            .stroke(lineWidth: line)
                            .frame(width: side, height: side)
                    case .slotting:
                        Capsule()
                            .frame(width: side, height: side * 0.45)
                    case .drilling:
                        Circle()
                            .frame(width: side, height: side)
                    case .counterbore:
                        ZStack {
                            Circle()
                                .inset(by: line / 2)
                                .stroke(lineWidth: line)
                            Circle()
                                .frame(width: side * 0.5, height: side * 0.5)
                        }
                        .frame(width: side, height: side)
                    case .boring:
                        Circle()
                            .inset(by: line / 2)
                            .stroke(lineWidth: line)
                            .frame(width: side, height: side)
                    case .threadMilling:
                        ThreadMillGlyph()
                            .stroke(style: StrokeStyle(lineWidth: max(1, size / 13), lineJoin: .round))
                            .frame(width: size, height: size)
                    case .chamfer:
                        ChamferGlyph()
                            .stroke(style: StrokeStyle(lineWidth: max(1, size / 9), lineCap: .round, lineJoin: .round))
                            .frame(width: size, height: size)
                    default:
                        Image(systemName: kind.symbol)
                            .font(.system(size: size))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 20) {
        ThreadMillGlyph().stroke(lineWidth: 1.5).frame(width: 64, height: 64)
        OperationIcon(kind: .threadMilling, size: 16)
        OperationIcon(kind: .drilling, size: 16)
    }
    .padding()
}
