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
            HStack(spacing: 6) {
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
                        pickFromLibrary()
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

                // Same as "Pick from Library" in the menu, without having to open it first.
                Button {
                    pickFromLibrary()
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Pick from the tool library")
            }
        }
    }

    private func pickFromLibrary() {
        Task {
            if let picked = await appModel.pickTool() {
                select(picked)
            }
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
