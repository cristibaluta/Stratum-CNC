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
        VStack(alignment: .leading, spacing: 3) {
            Text("OPERATION")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: kind.symbol)
                        .foregroundStyle(.secondary)

                    Text(kind.title)
                        .fontWeight(.semibold)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(kind.selectionHint ?? "What this toolpath does")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
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

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    private let tileSize = CGSize(width: 70, height: 56)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(OperationKind.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                }
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(group) { option in
                        tile(for: option)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: CGFloat(columns.count) * tileSize.width + CGFloat(columns.count - 1) * 6 + 20)
    }

    private func tile(for option: OperationKind) -> some View {
        let isSelected = option == kind

        return Button {
            kind = option
            isPresented = false
        } label: {
            VStack(spacing: 4) {
                Image(systemName: option.symbol)
                    .font(.system(size: 16))

                Text(option.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: tileSize.width, height: tileSize.height)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(option.selectionHint ?? option.title)
    }
}

#Preview {
    @Previewable @State var kind = OperationKind.contour
    OperationPicker(kind: $kind)
        .padding()
}
