//
//  ToolPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolPicker: View {

    enum Style {
        /// A labelled inspector row.
        case row
        /// Just the menu and the library button, to share a row with other controls.
        case compact
    }

    @Binding var tool: Tool
    var style: Style = .row
    /// Extra text for the menu's help (compact only), e.g. the preset that was just applied.
    var extraHelp: String? = nil
    var onToolPicked: ((Tool) -> Void)?

    @EnvironmentObject var appModel: AppModel

    /// The tool library opens in a popover here, instead of the app-wide sheet.
    @State private var showingLibrary = false

    var body: some View {
        switch style {
        case .row:
            InspectorRow(label: "Tool") {
                controls
            }
        case .compact:
            controls
        }
    }

    private var controls: some View {
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
                    Label {
                        Text("Pick from Library")
                    } icon: {
                        EndMillIcon(size: 14)
                    }
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
            .help(menuHelp)

            // Same as "Pick from Library" in the menu, without having to open it first.
            Button {
                pickFromLibrary()
            } label: {
                EndMillIcon(size: 15)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Pick from the tool library")
        }
        .popover(isPresented: $showingLibrary, arrowEdge: .leading) {
            ToolsSheet(store: appModel.toolsStore, onPick: { select($0) })
                .frame(width: 800, height: 600)
        }
    }

    private var menuHelp: String {
        let base = "Tool: \(title(for: tool))"
        guard style == .compact, let extraHelp else { return base }
        return "\(base)\n\(extraHelp)"
    }

    private func pickFromLibrary() {
        showingLibrary = true
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
