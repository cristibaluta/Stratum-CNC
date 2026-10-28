//
//  OperationPicker.swift
//  Stratum CNC
//

import SwiftUI

/// Chooses what the toolpath does. Same look as `ToolPicker`.
struct OperationPicker: View {
    @Binding var kind: OperationKind

    @State private var isPresented = false

    var body: some View {
        InspectorRow(label: "Type") {
            Button {
                isPresented.toggle()
            } label: {
                InspectorMenuLabel {
                    OperationIcon(kind: kind, size: 13)
                        .foregroundStyle(.secondary)
                    Text(kind.title)
                }
            }
            .buttonStyle(.plain)
            .help(kind.selectionHint ?? "What this toolpath does")
            .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                OperationGridPicker(kind: $kind, isPresented: $isPresented)
            }
        }
    }
}

/// The tooltip-style popover content: every operation, laid out as a grid of
/// icon + label tiles instead of `Menu`'s single vertical list.
private struct OperationGridPicker: View {
    @Binding var kind: OperationKind
    @Binding var isPresented: Bool

    @State private var hovered: OperationKind?

    private let width: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(OperationKind.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    // More air between the groups than between the rows inside one
                    Divider()
                        .padding(.vertical, 24)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(group) { option in
                        row(for: option)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: width)
    }

    private func row(for option: OperationKind) -> some View {
        let isSelected = option == kind

        return Button {
            kind = option
            isPresented = false
        } label: {
            HStack(alignment: .top, spacing: 12) {
                OperationIcon(kind: option, size: 18)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)

                    Text(option.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 6)
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
    @Previewable @State var kind = OperationKind.contour
    OperationPicker(kind: $kind)
        .padding()
}
