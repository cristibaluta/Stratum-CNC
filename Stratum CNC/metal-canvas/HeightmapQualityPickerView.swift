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
/// Meant to sit alongside `MaterialPanelView`/`ToolsPickerView` in the
/// canvas overlay, next to `CanvasSceneModel.heightmapCellSize`, the value
/// it edits.
struct HeightmapQualityPickerView: View {
    @Binding var cellSize: Float

    /// 0.1mm (best quality) through 0.5mm (fastest), in 0.1mm steps —
    /// matches `CanvasSceneModel.heightmapCellSize`'s documented range.
    private static let steps: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]

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
            case 0.1: quality = "Best"
            case 0.2: quality = "High"
            case 0.3: quality = "Medium"
            case 0.4: quality = "Low"
            default: quality = "Fastest"
        }
        return "\(quality) (\(String(format: "%.1f", step))mm)"
    }
}

#Preview {
    HeightmapQualityPickerView(cellSize: .constant(0.1))
        .padding()
}
