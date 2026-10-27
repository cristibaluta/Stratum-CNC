//
//  DirectionPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 22.09.2026.
//

import SwiftUI

/// Chooses which way the tool cuts relative to its rotation, as a segmented control.
struct DirectionPicker: View {
    @Binding var direction: CutDirectionOption

    var body: some View {
        InspectorRow(label: "Direction") {
            Picker("", selection: $direction) {
                ForEach(CutDirectionOption.allCases, id: \.self) { option in
                    Text(option.rawValue)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help(direction.selectionHint)
        }
    }
}

/// The tooltip-style popover content: both directions, laid out as a row of
/// glyph + label tiles instead of `Menu`'s single vertical list. Same layout and
/// tile styling as `ContourGridPicker`.
private struct DirectionGridPicker: View {
    @Binding var direction: CutDirectionOption
    @Binding var isPresented: Bool

    private let tileSize = CGSize(width: 96, height: 66)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CutDirectionOption.allCases, id: \.self) { option in
                expandedButton(for: option)
            }
            Spacer()
        }
    }

    private func expandedButton(for option: CutDirectionOption) -> some View {
        let isSelected = option == direction

        return Button {
            direction = option
            isPresented = false
        } label: {
            VStack(spacing: 4) {
                DirectionGlyph(direction: option, tint: isSelected ? Color.accentColor : .secondary)
                    .frame(width: 56, height: 36)

                Text(option.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: tileSize.width, height: tileSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .foregroundStyle(isSelected ? Color.accentColor : .primary)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .help(option.selectionHint)
    }
}

/// A small cut diagram: the tool (circle) against a wall of material (the shaded strip),
/// with its spin arrow inside and a travel arrow underneath.
///
/// The spindle always turns clockwise, so the tooth at the wall moves to the right. Climb
/// feeds the same way (travel arrow points right, the cutter's rotation and its travel
/// agree at the edge); conventional feeds against it (arrow points left). That is also the
/// clockwise / counter-clockwise loop of the cut around a pocket, same convention as before.
/// Drawn in a fixed 44x28 design space and scaled to whatever frame it's given.
private struct DirectionGlyph: View {
    let direction: CutDirectionOption
    var tint: Color = .primary

    private let designSize = CGSize(width: 44, height: 28)
    private var isClimb: Bool { direction == .climb }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / designSize.width, size.height / designSize.height)
            context.translateBy(x: (size.width - designSize.width * scale) / 2,
                                y: (size.height - designSize.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)

            let line = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            let wallY: CGFloat = 5
            let radius: CGFloat = 6.5
            let center = CGPoint(x: designSize.width / 2, y: wallY + radius)

            // Material, with its edge where the tool cuts.
            context.fill(Path(roundedRect: CGRect(x: 1, y: 0, width: designSize.width - 2, height: wallY),
                              cornerRadius: 1),
                         with: .color(Color.secondary.opacity(0.25)))
            var wall = Path()
            wall.move(to: CGPoint(x: 1, y: wallY))
            wall.addLine(to: CGPoint(x: designSize.width - 1, y: wallY))
            context.stroke(wall, with: .color(Color.secondary.opacity(0.7)), style: line)

            // The tool, resting on the wall, with its centre marked.
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2)),
                           with: .color(tint), style: line)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2)),
                         with: .color(tint))

            // Spindle rotation: a clockwise arc inside the tool.
            context.stroke(spinArrow(center: center, radius: radius * 0.58), with: .color(tint.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))

            // Travel of the tool along the wall.
            context.stroke(travelArrow(y: 23.5), with: .color(tint), style: line)
        }
    }

    /// Roughly three-quarters of a circle running clockwise (angles grow clockwise in a
    /// y-down space), with a small arrowhead tangent to its open end.
    private func spinArrow(center: CGPoint, radius: CGFloat) -> Path {
        let start: CGFloat = -.pi * 0.85
        let end: CGFloat = start + 1.45 * .pi
        let steps = 24

        var path = Path()
        for i in 0...steps {
            let angle = start + (end - start) * CGFloat(i) / CGFloat(steps)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }

        let tip = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
        let travel = end + .pi / 2
        let back: CGFloat = 2.4
        let span: CGFloat = 1.8
        let base = CGPoint(x: tip.x - back * cos(travel), y: tip.y - back * sin(travel))
        let normal = travel + .pi / 2
        path.move(to: CGPoint(x: base.x + span * cos(normal), y: base.y + span * sin(normal)))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: base.x - span * cos(normal), y: base.y - span * sin(normal)))
        return path
    }

    /// A horizontal arrow, pointing right for climb and left for conventional.
    private func travelArrow(y: CGFloat) -> Path {
        let left: CGFloat = 7
        let right: CGFloat = designSize.width - 7
        let sign: CGFloat = isClimb ? 1 : -1
        let tail = isClimb ? left : right
        let tip = isClimb ? right : left

        var path = Path()
        path.move(to: CGPoint(x: tail, y: y))
        path.addLine(to: CGPoint(x: tip, y: y))
        path.move(to: CGPoint(x: tip - sign * 3.6, y: y - 3))
        path.addLine(to: CGPoint(x: tip, y: y))
        path.addLine(to: CGPoint(x: tip - sign * 3.6, y: y + 3))
        return path
    }
}

private extension CutDirectionOption {
    var selectionHint: String {
        switch self {
            case .climb:        return "Cutter rotation and feed agree at the edge — smoother finish, lighter chips at the end of each pass."
            case .conventional: return "Cutter rotation and feed oppose at the edge — safer bite on rigid setups and older machines."
        }
    }
}

#Preview {
    @Previewable @State var direction = CutDirectionOption.climb
    DirectionPicker(direction: $direction)
        .padding()
}
