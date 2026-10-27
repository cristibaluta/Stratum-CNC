//
//  ContourPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI
import StratumCAM

protocol CutSideOption: CaseIterable, Hashable, RawRepresentable where RawValue == String {
    var position: SC.CutSide { get }
    /// What the picker's segments and tiles display.
    var label: String { get }
    var selectionHint: String { get }
}

extension SC.CutSide: @retroactive CaseIterable {
    public static let allCases: [SC.CutSide] = [.inside, .outside, .onContour]
}

extension SC.CutSide: CutSideOption {
    var position: SC.CutSide { self }
    var label: String {
        switch self {
            case .inside:    return "Inside"
            case .outside:   return "Outside"
            case .onContour: return "On Contour"
        }
    }
    var selectionHint: String {
        switch self {
            case .onContour: return "Tool centre follows the selected line exactly."
            case .inside:  return "Tool stays inside the selected shape, offset by its radius."
            case .outside: return "Tool stays outside the selected shape, offset by its radius."
        }
    }
}

/// Chooses which side of the selected shape the tool follows. Same look as `OperationPicker`:
/// a pop-up field that opens a list on its left, one drawn-and-explained row per side.
/// Generic so contour and chamfer -- the two operations with a side -- share one picker.
struct ContourPicker<Value: CutSideOption>: View {
    @Binding var selection: Value

    /// The row's label.
    var title: String = "Side"

    @State private var isPresented = false

    var body: some View {
        InspectorRow(label: title) {
            Button {
                isPresented.toggle()
            } label: {
                InspectorMenuLabel {
                    ContourTypeGlyph(position: selection.position, tint: .primary)
                        .frame(width: 22, height: 15)
                    Text(selection.label)
                }
            }
            .buttonStyle(.plain)
            .help(selection.selectionHint)
            .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                ContourOptionsPopover(selection: $selection, isPresented: $isPresented)
            }
        }
    }
}

/// The popover content: every side as a row of drawing + name + explanation.
private struct ContourOptionsPopover<Value: CutSideOption>: View {
    @Binding var selection: Value
    @Binding var isPresented: Bool

    @State private var hovered: Value?

    private let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Value.allCases), id: \.self) { option in
                row(for: option)
            }
        }
        .padding(10)
        .frame(width: width)
    }

    private func row(for option: Value) -> some View {
        let isSelected = option == selection

        return Button {
            selection = option
            isPresented = false
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ContourTypeGlyph(position: option.position,
                                 tint: isSelected ? Color.accentColor : .secondary)
                    .frame(width: 66, height: 44)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
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

/// A small plan view: the selected shape (solid outline, lightly shaded), the tool's path
/// (dashed) and the tool itself (circle with its centre marked) sitting on that path.
/// The path is offset from the shape by exactly the tool's radius, so the picture shows why:
/// inside keeps the tool's body within the shape, outside keeps it clear of it, and on
/// contour puts the tool's centre right on the line.
/// Drawn in a fixed 48x32 design space and scaled to whatever frame it's given.
private struct ContourTypeGlyph: View {
    let position: SC.CutSide
    var tint: Color = .primary

    private let designSize = CGSize(width: 48, height: 32)
    private let toolRadius: CGFloat = 3.5
    private let shape = CGRect(x: 10, y: 9, width: 28, height: 16)
    private let shapeCorner: CGFloat = 2.5

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / designSize.width, size.height / designSize.height)
            context.translateBy(x: (size.width - designSize.width * scale) / 2,
                                y: (size.height - designSize.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)

            let line = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)

            // The selected shape.
            let shapePath = Path(roundedRect: shape, cornerRadius: shapeCorner)
            context.fill(shapePath, with: .color(Color.secondary.opacity(0.12)))
            context.stroke(shapePath, with: .color(Color.secondary.opacity(0.65)), style: line)

            // The tool's path, offset from the shape by the tool's radius.
            let pathRect = shape.insetBy(dx: pathOffset, dy: pathOffset)
            context.stroke(Path(roundedRect: pathRect, cornerRadius: pathCornerRadius),
                           with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2.5, 2]))

            // The tool, centred on its path, with its centre marked.
            let center = CGPoint(x: shape.midX, y: pathRect.minY)
            let toolRect = CGRect(x: center.x - toolRadius, y: center.y - toolRadius,
                                  width: toolRadius * 2, height: toolRadius * 2)
            context.fill(Path(ellipseIn: toolRect), with: .color(tint.opacity(0.18)))
            context.stroke(Path(ellipseIn: toolRect), with: .color(tint), style: line)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2)),
                         with: .color(tint))
        }
    }

    /// Positive pulls the path in from the shape (inside), negative pushes it out past the
    /// shape (outside); zero traces the shape itself (on the line).
    private var pathOffset: CGFloat {
        switch position {
            case .onContour: return 0
            case .inside:    return toolRadius
            case .outside:   return -toolRadius
        }
    }

    private var pathCornerRadius: CGFloat {
        switch position {
            case .onContour: return shapeCorner
            case .inside:    return 1
            case .outside:   return shapeCorner + toolRadius
        }
    }
}

#Preview {
    @Previewable @State var side = SC.CutSide.inside
    ContourPicker(selection: $side)
        .padding()
        .frame(width: 260)
}
