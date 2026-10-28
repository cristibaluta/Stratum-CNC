//
//  RampTypeGlyph.swift
//  Stratum CNC
//
//  Custom drawing, moved out of RampingButton.swift.
//

import SwiftUI

/// A small drawing of how the tool gets down to the floor: straight down for
/// `.none`, a straight diagonal for `.linear`, a tightening spiral for `.helix`.
struct RampTypeGlyph: View {
    let type: RampType
    var tint: Color = .primary

    var body: some View {
        ZStack(alignment: .bottom) {
            // The floor the tool follows once it's down.
            Rectangle()
                .fill(Color.secondary.opacity(0.5))
                .frame(height: 1)

            switch type {
                case .none:
                    plunge
                case .linear:
                    ramp
                case .helix:
                    helix
            }
        }
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2, 1.6])
    }

    /// Straight down, no ramp.
    private var plunge: some View {
        Path { path in
            path.move(to: CGPoint(x: 9, y: 0))
            path.addLine(to: CGPoint(x: 9, y: 14))
        }
        .stroke(tint, style: strokeStyle)
    }

    /// A straight diagonal ramp down to the floor.
    private var ramp: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 18, y: 14))
        }
        .stroke(tint, style: strokeStyle)
    }

    /// A tightening spiral down to the floor.
    private var helix: some View {
        Circle()
            .trim(from: 0.08, to: 0.92)
            .stroke(tint, style: strokeStyle)
            .frame(width: 13, height: 13)
    }
}
