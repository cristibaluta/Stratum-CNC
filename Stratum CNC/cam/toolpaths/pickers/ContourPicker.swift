//
//  ContourPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// Any "which side of the boundary" choice the glyph can draw: inside, outside, or
/// straight along the line. `ContourType` (contour) and `ChamferSide` (chamfer) each
/// spell the same three positions with their own case names, so `ContourPicker` and its
/// glyph work from this instead of one concrete enum -- the icons are drawn once and
/// reused wherever a "side" is picked.
protocol CutSideOption: CaseIterable, Hashable, RawRepresentable where RawValue == String {
    var position: CutSidePosition { get }
    var selectionHint: String { get }
}

enum CutSidePosition {
    case inside, outside, onLine
}

extension ContourType: CutSideOption {
    var position: CutSidePosition {
        switch self {
            case .inside:  return .inside
            case .outside: return .outside
            case .outline: return .onLine
        }
    }

    var selectionHint: String {
        switch self {
            case .outline: return "Tool centre follows the selected line exactly."
            case .inside:  return "Tool stays inside the selected shape, offset by its radius."
            case .outside: return "Tool stays outside the selected shape, offset by its radius."
        }
    }
}

extension ChamferSide: CutSideOption {
    var position: CutSidePosition {
        switch self {
            case .inside:    return .inside
            case .outside:   return .outside
            case .onContour: return .onLine
        }
    }

    var selectionHint: String {
        switch self {
            case .outside:   return "Bevels the outside edge of the selected shape."
            case .inside:    return "Bevels the inside edge of the selected shape."
            case .onContour: return "Bevels straight along the selected line."
        }
    }
}

/// Chooses which side of the selected shape the tool follows. Same look as `OperationPicker`.
/// Generic so contour and chamfer -- the two operations with a side -- share one picker and
/// one glyph instead of each drawing their own.
struct ContourPicker<Value: CutSideOption>: View {
    @Binding var selection: Value

    /// Shown above the glyph button; "CONTOUR" for the contour operation, "SIDE" for chamfer.
    var title: String = "SIDE"

    /// When true, the options are laid out directly in the view instead of
    /// behind a button + popover.
    var expanded: Bool = false

    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if expanded {
                ContourGridPicker(selection: $selection, isPresented: .constant(false))
            } else {
                Button {
                    isPresented.toggle()
                } label: {
                    HStack(spacing: 5) {
                        ContourTypeGlyph(position: selection.position)
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(selection.selectionHint)
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    ContourGridPicker(selection: $selection, isPresented: $isPresented)
                        .padding(24)
                }
            }
        }
    }
}

/// The tooltip-style popover content: every side, laid out as a row of
/// glyph + label tiles instead of `Menu`'s single vertical list.
private struct ContourGridPicker<Value: CutSideOption>: View {
    @Binding var selection: Value
    @Binding var isPresented: Bool

    private let tileSize = CGSize(width: 70, height: 56)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Value.allCases), id: \.self) { option in
                expandedButton(for: option)
            }
            Spacer()
        }
    }

    private func expandedButton(for option: Value) -> some View {
        let isSelected = option == selection

        return Button {
            selection = option
            isPresented = false
        } label: {
            VStack(spacing: 4) {
                ContourTypeGlyph(position: option.position, tint: isSelected ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 22)

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

/// A small drawing of the part's boundary (solid) against the tool's path (dashed),
/// showing at a glance whether the tool runs inside, outside, or on the line.
private struct ContourTypeGlyph: View {
    let position: CutSidePosition
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
    /// out past the boundary (outside); zero traces the boundary itself (on the line).
    private var pathOffset: CGFloat {
        switch position {
            case .onLine:  return 0
            case .inside:  return 3
            case .outside: return -3
        }
    }

    private var pathCornerRadius: CGFloat {
        switch position {
            case .onLine:  return 2.5
            case .inside:  return 1
            case .outside: return 4
        }
    }
}

#Preview {
    @Previewable @State var selection = ContourType.outline
    ContourPicker(selection: $selection, title: "CONTOUR")
        .padding()
}
