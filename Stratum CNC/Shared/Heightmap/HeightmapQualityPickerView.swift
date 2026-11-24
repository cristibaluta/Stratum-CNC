//
//  HeightmapQualityPickerView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//


//
//  HeightmapQualityPickerView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import SwiftUI

/// Lets the user trade heightmap carve quality for speed by picking the
/// grid's cell size — smaller cells sample more of the surface (finer
/// detail, slower carve), larger cells sample less (coarser, faster).
/// Meant for a popover from the canvas overlay, next to
/// `CanvasSceneModel.heightmapCellSize`, the value it edits.
///
/// Every option is listed right away, one row each with the current one checked, rather
/// than behind a pop-up field.
struct HeightmapQualityPickerView: View {
    @Binding var cellSize: Float
    /// Called after a row was picked, so the owner can close its popover.
    var onSelect: () -> Void = {}

    @State private var hovered: Float?

    /// 0.05mm (finest, the GPU path only caps it at 2048 samples a side) through 0.5mm (fastest).
    private static let steps: [Float] = [0.05, 0.1, 0.2, 0.3, 0.5]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Heightmap Quality")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            ForEach(Self.steps, id: \.self) { step in
                row(for: step)
            }
        }
    }

    private func row(for step: Float) -> some View {
        let isSelected = step == cellSize

        return Button {
            cellSize = step
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 14)

                Text(quality(for: step))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                Spacer(minLength: 12)

                Text("\(step.fixed(step < 0.1 ? 2 : 1)) mm")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15)
                                   : (hovered == step ? Color.primary.opacity(0.06) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? step : (hovered == step ? nil : hovered)
        }
    }

    private func quality(for step: Float) -> String {
        switch step {
            case 0.05: "Finest"
            case 0.1: "Best"
            case 0.2: "High"
            case 0.3: "Medium"
            default: "Fastest"
        }
    }
}

#Preview {
    HeightmapQualityPickerView(cellSize: .constant(0.1))
        .padding()
}
