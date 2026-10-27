//
//  RampingButton.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// Same look as `OperationPicker`: a labelled pop-up button that opens the ramping editor.
struct RampingButton: View {
    @Binding var ramping: RampingSettings
    /// The ramp types the operation accepts, in the order they are offered.
    var available: [RampType] = RampType.allCases
    let action: () -> Void

    private var shownType: RampType { ramping.enabled ? ramping.type : .none }

    var body: some View {
        InspectorRow(label: "Entry") {
            Button(action: action) {
                InspectorMenuLabel {
                    RampTypeGlyph(type: shownType, tint: ramping.enabled ? .primary : .secondary)
                        .frame(width: 18, height: 14)
                    Text(ramping.enabled ? ramping.type.rawValue : "Off")
                }
            }
            .buttonStyle(.plain)
            .help("Ramp angle, length, return path and spiral direction")
        }
    }
}

private extension RampType {
    var rampSelectionHint: String {
        switch self {
            case .none:   return "The tool plunges straight down."
            case .linear: return "The tool descends at an angle before cutting."
            case .helix:  return "The tool spirals down to depth."
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

/// Tile-sized artwork for the expanded ramp picker: a part boundary against the
/// entry path, same convention as `ContourTypeGlyph` / `DirectionGlyph` /
/// `PatternGlyph` — separate from `RampTypeGlyph` above, which is drawn for the
/// much smaller compact trigger and doesn't carry a boundary at that size.
private struct RampTypeTileGlyph: View {
    let type: RampType
    var tint: Color = .primary

    private let partInset: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            entryPath(in: proxy.size)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2, 1.6]))
        }
    }

    private func entryPath(in size: CGSize) -> Path {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: partInset + 4, dy: partInset + 3)
        switch type {
            case .none:   return plungePath(in: rect)
            case .linear: return linearPath(in: rect)
            case .helix:  return helixPath(in: rect)
        }
    }

    /// Straight down, no ramp.
    private func plungePath(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        return path
    }

    /// A straight diagonal ramp down to the floor.
    private func linearPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }

    /// A tightening spiral down to the floor, seen from the side as nested arcs.
    private func helixPath(in rect: CGRect) -> Path {
        var path = Path()
        let turns = 3
        let step = rect.height / CGFloat(turns * 2)
        for i in 0..<(turns * 2) {
            let y0 = rect.minY + CGFloat(i) * step
            let y1 = y0 + step
            let x0 = i.isMultiple(of: 2) ? rect.minX : rect.maxX
            let x1 = i.isMultiple(of: 2) ? rect.maxX : rect.minX
            if i == 0 {
                path.move(to: CGPoint(x: x0, y: y0))
            }
            path.addQuadCurve(to: CGPoint(x: x1, y: y1),
                               control: CGPoint(x: i.isMultiple(of: 2) ? rect.maxX : rect.minX, y: (y0 + y1) / 2))
        }
        return path
    }
}

#Preview {
    @Previewable @State var ramping = RampingSettings(enabled: true, type: .helix, angle: 3, length: 10)
    RampingButton(ramping: $ramping) {}
        .padding()
}
