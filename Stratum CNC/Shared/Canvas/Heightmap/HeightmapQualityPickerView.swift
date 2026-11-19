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
/// Meant to sit alongside `MaterialPanelView`/`ToolChipsView` in the
/// canvas overlay, next to `CanvasSceneModel.heightmapCellSize`, the value
/// it edits.
struct HeightmapQualityPickerView: View {
    @Binding var cellSize: Float

    /// 0.05mm (finest, the GPU path only caps it at 2048 samples a side) through 0.5mm (fastest).
    private static let steps: [Float] = [0.05, 0.1, 0.2, 0.3, 0.5]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Heightmap Quality")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Picker("", selection: $cellSize) {
                ForEach(Self.steps, id: \.self) { step in
                    Text(label(for: step)).tag(step)
                }
            }
            .labelsHidden()
        }
    }

    private func label(for step: Float) -> String {
        let quality: String
        switch step {
            case 0.05: quality = "Finest"
            case 0.1: quality = "Best"
            case 0.2: quality = "High"
            case 0.3: quality = "Medium"
            default: quality = "Fastest"
        }
        return "\(quality) (\(step.fixed(step < 0.1 ? 2 : 1))mm)"
    }
}

#Preview {
    HeightmapQualityPickerView(cellSize: .constant(0.1))
        .padding()
}
