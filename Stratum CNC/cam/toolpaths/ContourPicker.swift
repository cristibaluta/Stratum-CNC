//
//  ContourPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// Chooses which side of the selected shape the tool follows. Same look as `OperationPicker`.
struct ContourPicker: View {
    @Binding var selection: ContourType

    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CONTOUR")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 5) {
                    ContourTypeGlyph(type: selection)
                        .frame(width: 18, height: 14)

                    Text(selection.rawValue)
                        .fontWeight(.semibold)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help(selection.selectionHint)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                ContourGridPicker(selection: $selection, isPresented: $isPresented)
            }
        }
    }
}

/// The tooltip-style popover content: every contour side, laid out as a row of
/// glyph + label tiles instead of `Menu`'s single vertical list.
private struct ContourGridPicker: View {
    @Binding var selection: ContourType
    @Binding var isPresented: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    private let tileSize = CGSize(width: 70, height: 56)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(ContourType.allCases, id: \.self) { option in
                tile(for: option)
            }
        }
        .padding(10)
        .frame(width: CGFloat(columns.count) * tileSize.width + CGFloat(columns.count - 1) * 6 + 20)
    }

    private func tile(for option: ContourType) -> some View {
        let isSelected = option == selection

        return Button {
            selection = option
            isPresented = false
        } label: {
            VStack(spacing: 4) {
                ContourTypeGlyph(type: option, tint: isSelected ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 22)

                Text(option.rawValue)
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
        .help(option.selectionHint)
    }
}

/// A small drawing of the part's boundary (solid) against the tool's path (dashed),
/// showing at a glance whether the tool runs inside, outside, or on the line.
private struct ContourTypeGlyph: View {
    let type: ContourType
    var tint: Color = .primary

    /// How far the part boundary sits from the glyph's own frame, so the "outside"
    /// path — which is drawn further out still — has room to breathe.
    private let partInset: CGFloat = 5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .inset(by: partInset)
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1.25)

            RoundedRectangle(cornerRadius: pathCornerRadius)
                .inset(by: partInset + pathOffset)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.25, dash: [2, 1.6]))
        }
    }

    /// Positive pulls the path in from the boundary (inside), negative pushes it
    /// out past the boundary (outside); zero traces the boundary itself (outline).
    private var pathOffset: CGFloat {
        switch type {
            case .outline: return 0
            case .inside:  return 3
            case .outside: return -3
        }
    }

    private var pathCornerRadius: CGFloat {
        switch type {
            case .outline: return 2.5
            case .inside:  return 1
            case .outside: return 4
        }
    }
}

private extension ContourType {
    var selectionHint: String {
        switch self {
            case .outline: return "Tool centre follows the selected line exactly."
            case .inside:  return "Tool stays inside the selected shape, offset by its radius."
            case .outside: return "Tool stays outside the selected shape, offset by its radius."
        }
    }
}

#Preview {
    @Previewable @State var selection = ContourType.outline
    ContourPicker(selection: $selection)
        .padding()
}
