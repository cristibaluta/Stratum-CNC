//
//  FacingAnglePresets.swift
//  Stratum CNC
//
//  Three icons after the facing's Angle field that set the usual directions in one click:
//  vertical lines (90°), angled lines (45°) and horizontal lines (0°). The icon matching the
//  current angle is drawn in the accent colour; any other angle typed into the field leaves
//  all three plain. Same pattern as `FacingSidesButton` / `FeedCalculatorButton`.
//

import SwiftUI

/// The row of three preset buttons. 0° runs the passes along X (horizontal lines on the
/// canvas), 90° along Y (vertical lines).
struct FacingAnglePresets: View {
    @Binding var angle: Double

    private struct Preset: Identifiable {
        let degrees: Double
        let name: String
        var id: Double { degrees }
    }

    private static let presets: [Preset] = [
        Preset(degrees: 90, name: "Vertical"),
        Preset(degrees: 45, name: "Angled"),
        Preset(degrees: 0, name: "Horizontal")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.presets) { preset in
                HoverIconButton {
                    angle = preset.degrees
                } label: {
                    FacingAngleIcon(degrees: preset.degrees, isOn: isCurrent(preset))
                        .frame(width: 20, height: 18)
                }
                // Shares the row with the field: without this the icons are the first thing squeezed out.
                .fixedSize()
                .layoutPriority(1)
                .help("\(preset.name) passes (\(Int(preset.degrees))°)")
                .accessibilityLabel("\(preset.name) passes, \(Int(preset.degrees)) degrees")
            }
        }
        .fixedSize()
        .layoutPriority(1)
    }

    private func isCurrent(_ preset: Preset) -> Bool {
        abs(angle - preset.degrees) < 0.001
    }
}

/// A rounded square crossed by three parallel lines at `degrees` (0 = horizontal, counter-clockwise
/// like the canvas, so 45 rises to the right).
struct FacingAngleIcon: View {
    let degrees: Double
    let isOn: Bool

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) - 2
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                              width: side, height: side)
            let color: Color = isOn ? .accentColor : .secondary

            // Direction of the lines; Y is up on the canvas but down in a `Canvas`.
            let radians = degrees * .pi / 180
            let along = CGVector(dx: cos(radians), dy: -sin(radians))
            let across = CGVector(dx: -along.dy, dy: along.dx)
            let reach = side            // longer than the diagonal, the clip trims it
            let spacing = side / 4
            let center = CGPoint(x: rect.midX, y: rect.midY)

            var frame = Path(roundedRect: rect, cornerRadius: 2.5)
            context.stroke(frame, with: .color(color.opacity(0.6)), lineWidth: 1)
            frame = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2)

            context.clip(to: frame)
            for index in -1...1 {
                let offset = CGFloat(index) * spacing
                let origin = CGPoint(x: center.x + across.dx * offset, y: center.y + across.dy * offset)
                var line = Path()
                line.move(to: CGPoint(x: origin.x - along.dx * reach, y: origin.y - along.dy * reach))
                line.addLine(to: CGPoint(x: origin.x + along.dx * reach, y: origin.y + along.dy * reach))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
    }
}

#Preview {
    @Previewable @State var angle = 45.0
    HStack {
        Text("\(Int(angle))°")
        FacingAnglePresets(angle: $angle)
    }
    .padding()
}
