//
//  CalculatorGlyph.swift
//  Stratum CNC
//
//  A calculator drawn in the app: SF Symbols only has "calculator" from macOS 15, and the app
//  still runs on macOS 14. Same drawing style as `ThreadMillShape`: an outline plus filled keys,
//  following whatever foreground style it is given.
//

import SwiftUI

/// The calculator's body and display, drawn in the unit square. Stroke it.
struct CalculatorOutlineShape: Shape {

    func path(in rect: CGRect) -> Path {
        func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
            CGRect(x: rect.minX + x0 * rect.width, y: rect.minY + y0 * rect.height,
                   width: (x1 - x0) * rect.width, height: (y1 - y0) * rect.height)
        }

        var p = Path()
        // Body
        p.addRoundedRect(in: box(0.16, 0.05, 0.84, 0.95),
                         cornerSize: CGSize(width: rect.width * 0.12, height: rect.width * 0.12))
        // Display
        p.addRoundedRect(in: box(0.28, 0.17, 0.72, 0.35),
                         cornerSize: CGSize(width: rect.width * 0.04, height: rect.width * 0.04))
        return p
    }
}

/// The calculator's keys: a 3 x 3 grid of dots, drawn in the unit square. Fill it.
struct CalculatorKeysShape: Shape {

    func path(in rect: CGRect) -> Path {
        let radius = 0.05
        var p = Path()
        for x in [0.34, 0.5, 0.66] {
            for y in [0.5, 0.65, 0.8] {
                p.addEllipse(in: CGRect(x: rect.minX + (x - radius) * rect.width,
                                        y: rect.minY + (y - radius) * rect.height,
                                        width: 2 * radius * rect.width,
                                        height: 2 * radius * rect.height))
            }
        }
        return p
    }
}

/// A calculator icon. Sized like `Image(systemName:).font(.system(size:))`; colour it with
/// `foregroundStyle`.
struct CalculatorIcon: View {
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            CalculatorOutlineShape()
                .stroke(style: StrokeStyle(lineWidth: max(1, size / 13), lineJoin: .round))
            CalculatorKeysShape()
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        CalculatorIcon(size: 12)
        CalculatorIcon(size: 16)
        CalculatorIcon(size: 32)
    }
    .padding()
}
