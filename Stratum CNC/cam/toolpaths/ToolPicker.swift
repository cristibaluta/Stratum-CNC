//
//  ToolPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolPicker: View {
    @Binding var tool: Tool

    /// When true, the tool list is laid out directly in the view instead of
    /// behind a menu button.
    var expanded: Bool = false

    @EnvironmentObject var appModel: AppModel

    /// Hardcoded for now — later this should be the actual most-recently/most-often
    /// used tools, probably persisted on `AppModel` or read from the library.
    fileprivate static let mostUsedTools: [Tool] = [
        Tool(id: UUID(),
             name: "1mm End Mill",
             shankDiameter: 3.175,
             toolDiameter: 1,
             length: 12,
             type: .endMill,
             group: nil,
             tipAngle: nil,
             parameters: [:]),
        Tool(id: UUID(),
             name: "2mm End Mill",
             shankDiameter: 3.175,
             toolDiameter: 2,
             length: 12,
             type: .endMill,
             group: nil,
             tipAngle: nil,
             parameters: [:]),
        Tool(id: UUID(),
             name: "3.175mm End Mill",
             shankDiameter: 3.175,
             toolDiameter: 3.175,
             length: 12,
             type: .endMill,
             group: nil,
             tipAngle: nil,
             parameters: [:]),
        Tool(id: UUID(),
             name: "6mm End Mill",
             shankDiameter: 6,
             toolDiameter: 6,
             length: 20,
             type: .endMill,
             group: nil,
             tipAngle: nil,
             parameters: [:]),
        Tool(id: UUID(),
             name: "0.8mm Drill",
             shankDiameter: 3.175,
             toolDiameter: 0.8,
             length: 12,
             type: .drill,
             group: nil,
             tipAngle: 118,
             parameters: [:])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TOOL")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if expanded {
                ToolGridPicker(tool: $tool) {
                    appModel.showingToolsSheet = true
                }
            } else {
                Menu {
                    ForEach(Self.mostUsedTools) { candidate in
                        Button {
                            tool = candidate
                        } label: {
                            if candidate.id == tool.id {
                                Label(title(for: candidate), systemImage: "checkmark")
                            } else {
                                Text(title(for: candidate))
                            }
                        }
                    }

                    Divider()

                    Button {
                        appModel.showingToolsSheet = true
                    } label: {
                        Label("Tool Library…", systemImage: "wrench.and.screwdriver")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("T\(tool.displayName)")
                            .fontWeight(.semibold)

                        Text("Ø\(tool.toolDiameter, specifier: "%.1f")")
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }

    private func title(for candidate: Tool) -> String {
        "\(candidate.name) — Ø\(String(format: "%.2f", candidate.toolDiameter))"
    }
}

/// The expanded, in-view counterpart to `ToolPicker`'s menu: every most-used
/// tool as a tile, same tile language as `OperationGridPicker` / `ContourGridPicker`,
/// plus a way into the full library.
private struct ToolGridPicker: View {
    @Binding var tool: Tool
    let onLibrary: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ToolPicker.mostUsedTools) { candidate in
                    tile(for: candidate)
                }
            }

            Button(action: onLibrary) {
                Label("Tool Library…", systemImage: "wrench.and.screwdriver")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func tile(for candidate: Tool) -> some View {
        let isSelected = candidate.id == tool.id

        return Button {
            tool = candidate
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("T\(candidate.displayName)")
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Text("Ø\(candidate.toolDiameter, specifier: "%.2f")")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemFill))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(candidate.name)
    }
}

#Preview {
    @Previewable @State var tool = ToolPicker.mostUsedTools[2]
    ToolPicker(tool: $tool)
        .environmentObject(AppModel())
        .padding()
}
