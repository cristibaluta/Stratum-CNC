//
//  DirectionPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 22.09.2026.
//

import SwiftUI

/// Chooses which way the tool cuts relative to its rotation. Same look as `OperationPicker`:
/// a pop-up field that opens a list on its left, one drawn-and-explained row per direction.
struct DirectionPicker: View {
    @Binding var direction: CutDirectionOption

    @State private var isPresented = false

    var body: some View {
        InspectorRow(label: "Direction") {
            Button {
                isPresented.toggle()
            } label: {
                InspectorMenuLabel {
                    DirectionGlyph(direction: direction, tint: .primary)
                        .frame(width: 22, height: 15)
                    Text(direction.rawValue)
                }
            }
            .buttonStyle(.plain)
            .help(direction.selectionHint)
            .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                DirectionOptionsPopover(direction: $direction, isPresented: $isPresented)
            }
        }
    }
}

/// The popover content: both directions as a row of drawing + name + explanation.
private struct DirectionOptionsPopover: View {
    @Binding var direction: CutDirectionOption
    @Binding var isPresented: Bool

    @State private var hovered: CutDirectionOption?

    private let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(CutDirectionOption.allCases, id: \.self) { option in
                row(for: option)
            }
        }
        .padding(10)
        .frame(width: width)
    }

    private func row(for option: CutDirectionOption) -> some View {
        let isSelected = option == direction

        return Button {
            direction = option
            isPresented = false
        } label: {
            HStack(alignment: .center, spacing: 12) {
                DirectionGlyph(direction: option,
                               tint: isSelected ? Color.accentColor : .secondary)
                    .frame(width: 66, height: 44)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)

                    Text(option.selectionHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isSelected: isSelected, isHovered: hovered == option))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? option : (hovered == option ? nil : hovered)
        }
    }

    private func rowBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        }
        return isHovered ? Color.primary.opacity(0.06) : Color.clear
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
