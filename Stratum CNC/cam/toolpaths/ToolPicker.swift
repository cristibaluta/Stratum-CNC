//
//  ToolPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolPicker: View {
    @Binding var tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TOOL")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Menu {
//                Button("T1 — Ø3 mm") {
//                    tool = Tool(
//                        number: 1,
//                        diameter: 3,
//                        name: "3 mm End Mill"
//                    )
//                }
//
//                Button("T2 — Ø6 mm") {
//                    tool = Tool(
//                        number: 2,
//                        diameter: 6,
//                        name: "6 mm End Mill"
//                    )
//                }
//
//                Button("T3 — Ø10 mm") {
//                    tool = Tool(
//                        number: 3,
//                        diameter: 10,
//                        name: "10 mm End Mill"
//                    )
//                }
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
