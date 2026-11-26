//
//  OperationGridPickerTwoColumns.swift
//  Stratum CNC
//
//  An alternative to `OperationGridPicker`: the same four categories with a separator between
//  them, but the operations inside each category sit in two columns (icon, title and a small summary). Which one `OperationPicker` shows is its
//  `usesTwoColumnPopover`.
//

import SwiftUI
import StratumCAM

struct OperationGridPickerTwoColumns: View {
    var selected: SC.MachiningOperation.Kind?
    var onSelect: (SC.MachiningOperation.Kind) -> Void

    @State private var hovered: SC.MachiningOperation.Kind?

    private let width: CGFloat = 560
    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(SC.MachiningOperation.Kind.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                        .padding(.vertical, 10)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(group) { option in
                        tile(for: option)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: width)
    }

    private func tile(for option: SC.MachiningOperation.Kind) -> some View {
        let isSelected = option == selected

        return Button {
            onSelect(option)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                OperationIcon3D(kind: option, size: 56, isSelected: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .lineLimit(1)

                    Text(option.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(isSelected: isSelected, isHovered: hovered == option))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? option : (hovered == option ? nil : hovered)
        }
    }

    private func background(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        }
        return isHovered ? Color.primary.opacity(0.06) : Color.clear
    }
}
