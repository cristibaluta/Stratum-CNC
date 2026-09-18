//
//  ToolsPickerView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import SwiftUI

/// Lists every distinct tool number the loaded program calls out (via
/// `T…`/`M6`) with a picker to assign each one a `ToolSpec`. Meant to sit
/// alongside `MaterialPanelView` in the canvas overlay — knowing the stock
/// and knowing what each tool actually is belong together.
struct ToolsPickerView: View {
    let tools: [Int]
    @Binding var assignments: [Int: ToolSpec]
    /// Specs the loaded file's own header declares, by tool number. Offered
    /// first in that tool's list, since it's what the CAM actually used.
    var fileSpecs: [Int: ToolSpec] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tools, id: \.self) { tool in

                HStack(alignment: .center, spacing: 2) {
                    Text("T\(tool)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    Picker("", selection: binding(for: tool)) {
                        Text("Unassigned").tag(ToolSpec?.none)
                        if let fileSpec = fileSpecs[tool] {
                            Text(fileSpec.name).tag(ToolSpec?.some(fileSpec))
                            Divider()
                        }
                        ForEach(ToolSpec.library) { spec in
                            Text(spec.name).tag(ToolSpec?.some(spec))
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private func binding(for tool: Int) -> Binding<ToolSpec?> {
        Binding(
            get: { assignments[tool] },
            set: { assignments[tool] = $0 }
        )
    }
}
