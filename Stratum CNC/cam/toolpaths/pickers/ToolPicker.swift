//
//  ToolPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolPicker: View {
    @Binding var tool: Tool

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

    private func title(for candidate: Tool) -> String {
        "\(candidate.name) — Ø\(String(format: "%.2f", candidate.toolDiameter))"
    }
}

#Preview {
    @Previewable @State var tool = ToolPicker.mostUsedTools[2]
    ToolPicker(tool: $tool)
        .environmentObject(AppModel())
        .padding()
}
