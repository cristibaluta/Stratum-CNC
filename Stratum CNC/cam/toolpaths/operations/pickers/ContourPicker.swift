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

    /// Just the button, at its natural width and without the label column, to share a row.
    var isCompact: Bool = false

    @State private var isPresented = false

    var body: some View {
        if isCompact {
            button
                .fixedSize(horizontal: true, vertical: false)
        } else {
            InspectorRow(label: title) {
                button
            }
        }
    }

    private var button: some View {
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
        .help("\(title): \(selection.selectionHint)")
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
            ContourOptionsPopover(selection: $selection, isPresented: $isPresented)
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

#Preview {
    @Previewable @State var side = SC.CutSide.inside
    ContourPicker(selection: $side)
        .padding()
        .frame(width: 260)
}
