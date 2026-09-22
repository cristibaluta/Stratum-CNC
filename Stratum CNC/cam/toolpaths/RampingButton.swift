//
//  RampingButton.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// Same look as `OperationPicker` / `ContourPicker`: an icon + label + chevron
/// that opens the ramping editor. The editor itself is unchanged — this file
/// only draws the trigger.
struct RampingButton: View {
    let ramping: RampingSettings
    let action: () -> Void

    private var shownType: RampType { ramping.enabled ? ramping.type : .none }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {

            Text("RAMPING")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Button(action: action) {
                HStack(spacing: 5) {
                    RampTypeGlyph(type: shownType, tint: ramping.enabled ? .primary : .secondary)
                        .frame(width: 18, height: 14)

                    Text(ramping.enabled ? ramping.type.rawValue : "Off")
                        .fontWeight(.semibold)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
    }
}

/// A small drawing of how the tool gets down to the floor: straight down for
/// `.none`, a straight diagonal for `.linear`, a tightening spiral for `.helix`.
private struct RampTypeGlyph: View {
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

#Preview {
    RampingButton(ramping: RampingSettings(enabled: true, type: .helix, angle: 3, length: 10)) {}
        .padding()
}
