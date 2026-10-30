//
//  PatternPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 22.09.2026.
//

import SwiftUI

/// Chooses how a pocket is cleared. Same look as `OperationPicker`: a pop-up field that
/// opens a list on its left, one drawn-and-explained row per pattern.
struct PatternPicker: View {
    @Binding var pattern: PocketPattern

    /// The patterns on offer, in order -- what the operation accepts, as the library says.
    var available: [PocketPattern] = PocketPattern.allCases

    /// Just the button, at its natural width and without the label column, to share a row.
    var isCompact: Bool = false

    @State private var isPresented = false

    var body: some View {
        if isCompact {
            button
                .fixedSize(horizontal: true, vertical: false)
        } else {
            InspectorRow(label: "Clearing pattern") {
                button
            }
        }
    }

    private var button: some View {
        Button {
            isPresented.toggle()
        } label: {
            InspectorMenuLabel {
                PatternGlyph(pattern: pattern)
                    .frame(width: 18, height: 14)
                Text(pattern.rawValue)
            }
        }
        .buttonStyle(.plain)
        .help(isCompact ? "Clearing pattern: \(pattern.selectionHint)" : pattern.selectionHint)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
            PatternOptionsPopover(pattern: $pattern, available: available, isPresented: $isPresented)
        }
    }
}

/// The popover content: every pattern as a row of drawing + name + explanation.
private struct PatternOptionsPopover: View {
    @Binding var pattern: PocketPattern
    let available: [PocketPattern]
    @Binding var isPresented: Bool

    @State private var hovered: PocketPattern?

    private let width: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(available, id: \.self) { option in
                row(for: option)
            }
        }
        .padding(10)
        .frame(width: width)
    }

    private func row(for option: PocketPattern) -> some View {
        let isSelected = option == pattern

        return Button {
            pattern = option
            isPresented = false
        } label: {
            HStack(alignment: .center, spacing: 12) {
                PatternGlyph(pattern: option, tint: isSelected ? Color.accentColor : .secondary)
                    .frame(width: 60, height: 44)
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

private extension PocketPattern {
    var selectionHint: String {
        switch self {
            case .offset:     return "Clears with rings that follow the pocket's shape, working inward."
            case .raster:     return "Clears with straight back-and-forth passes."
            case .spiral:     return "Clears with a continuous, tightening spiral."
            case .trochoidal: return "Clears with small looping passes, easing tool load in slots and tight corners."
            case .concentric: return "Clears with rings that expand outward."
            case .adaptive:   return "Clears with a constant, light radial load: opens up from a helix in the middle, so the tool never buries itself in corners."
        }
    }
}

#Preview {
    @Previewable @State var pattern = PocketPattern.spiral
    PatternPicker(pattern: $pattern)
        .padding()
}
