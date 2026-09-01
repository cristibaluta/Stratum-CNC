//
//  ToolParametersMatrix.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 27.08.2026.
//

import SwiftUI

struct ToolParametersMatrix: View {
    let tool: Tool

    private let columns = [
        GridItem(.fixed(120), alignment: .leading),
        GridItem(.flexible(), alignment: .trailing),
        GridItem(.flexible(), alignment: .trailing),
        GridItem(.flexible(), alignment: .trailing),
        GridItem(.flexible(), alignment: .trailing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {

            // Header
            headerCell("Material", alignment: .leading)
            headerCell("Spindle RPM")
            headerCell("Feed Rate")
            headerCell("Plunge Feed")
            headerCell("Depth of Cut")

            // Rows
            ForEach(tool.parameters.keys.sorted(), id: \.self) { material in
                if let parameters = tool.parameters[material] {
                    cell(material.capitalized, alignment: .leading)
                    cell("\(parameters.spindleRPM ?? -1)")
                    cell("\(parameters.feedRate ?? -1)")
                    cell("\(parameters.plungeFeedRate ?? -1)")
                    cell(format(parameters.depthOfCut ?? -1))
                }
            }
        }
        .padding()
    }

    private func headerCell(_ text: String, alignment: Alignment = .trailing) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.vertical, 10)
    }

    private func cell(_ text: String, alignment: Alignment = .trailing) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Divider()
            }
    }

    private func format(_ value: Double) -> String {
        value == floor(value)
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}
