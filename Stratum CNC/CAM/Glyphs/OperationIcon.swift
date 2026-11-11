//
//  OperationIcon.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 11.11.2026.
//

import SwiftUI
import StratumCAM

/// The icon of an operation: its SF Symbol, or a drawing of its own where SF Symbols have
/// nothing fitting (the thread mill). Sized like `Image(systemName:).font(.system(size:))`;
/// colour it with `foregroundStyle`.
struct OperationIcon: View {
    let kind: SC.MachiningOperation.Kind
    /// A rest operation has the icon of its own, not of the pocket it is made from.
    var isRest: Bool = false
    var size: CGFloat = 16

    var body: some View {
        if isRest {
            Image(systemName: "angle")
                .font(.system(size: size))
        } else if kind == .threadMilling {
            ThreadMillGlyph()
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
        ThreadMillGlyph().stroke(lineWidth: 1.5).frame(width: 64, height: 64)
        OperationIcon(kind: .threadMilling, size: 16)
        OperationIcon(kind: .drilling, size: 16)
    }
    .padding()
}
