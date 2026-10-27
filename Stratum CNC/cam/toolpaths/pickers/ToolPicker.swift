//
//  ToolPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolPicker: View {

    @Binding var tool: Tool
    var onToolPicked: ((Tool) -> Void)?

    @EnvironmentObject var appModel: AppModel

    var body: some View {
        InspectorRow(label: "Tool") {
            Menu {
                // The last 5 tools used, most recent first (persisted in UserDefaults).
                ForEach(appModel.recentTools) { candidate in
                    Button {
                        select(candidate)
                    } label: {
                        if candidate.id == tool.id {
                            Label(title(for: candidate), systemImage: "checkmark")
                        } else {
                            Text(title(for: candidate))
                        }
                    }
                }

                if !appModel.recentTools.isEmpty {
                    Divider()
                }

                Button {
                    Task {
                        if let picked = await appModel.pickTool() {
                            select(picked)
                        }
                    }
                } label: {
                    Label("Pick from Library", systemImage: "wrench.and.screwdriver")
                }
            } label: {
                InspectorMenuLabel {
                    Text("T\(tool.displayName)")
                    Text("Ø\(tool.toolDiameter, specifier: "%.1f")")
                        .foregroundStyle(.secondary)
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
    }

    private func select(_ candidate: Tool) {
        tool = candidate
        appModel.noteToolUsed(candidate)
        onToolPicked?(candidate)
    }

    private func title(for candidate: Tool) -> String {
        "\(candidate.name) — Ø\(String(format: "%.2f", candidate.toolDiameter))"
    }
}
