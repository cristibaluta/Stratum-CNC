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
                    .frame(width: 90, height: 60)
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

private extension CutDirectionOption {
    var selectionHint: String {
        switch self {
            case .climb:        return "Each tooth bites at full chip thickness and leaves at the finished wall with none. Usually the better finish and less tool wear, but it pulls the tool into the cut, so it needs a rigid setup without backlash."
            case .conventional: return "Each tooth starts at the finished wall with no chip and leaves at full thickness. It rubs before it bites, which wears the tool faster, but it is safer on machines with backlash or a loose setup."
        }
    }
}

#Preview {
    @Previewable @State var direction = CutDirectionOption.climb
    DirectionPicker(direction: $direction)
        .padding()
}
