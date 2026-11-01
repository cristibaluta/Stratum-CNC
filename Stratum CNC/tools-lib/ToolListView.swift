//
//  ToolListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct ToolListView: View {

    let tools: [Tool]

    @Binding var selectedToolID: Tool.ID?
    @Binding var filter: ToolFilter

    /// Used to name a tool's source in the stock pill's tooltip. Choosing a source, and adding
    /// or importing tools, live in the rail's footer.
    let sources: [ToolSourceInfo]

    let onDuplicate: (Tool) -> Void
    let onDelete: (Tool) -> Void

    private var sourcesByID: [UUID: ToolSourceInfo] {
        Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let sourcesByID = sourcesByID
        List(selection: $selectedToolID) {
            ForEach(tools) { tool in
                ToolRow(
                    tool: tool,
                    sourceName: sourcesByID[tool.sourceID]?.name
                )
                    // Skips rebuilding a row whose tool hasn't changed. Without it every row
                    // is rebuilt each time the selection moves, and a row's title works
                    // through the tool's name, group and presets.
                    .equatable()
                    .tag(tool.id)
                    .contextMenu {
                        Button {
                            onDuplicate(tool)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }

                        Divider()

                        Button(role: .destructive) {
                            onDelete(tool)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.toolColumnBackground)
        .overlay {
            if tools.isEmpty {
                emptyState
            }
        }
        .navigationTitle("Tool Library")
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(filter.isFiltering ? "No tools match" : "No tools here", systemImage: "tray")
        } description: {
            if filter.isFiltering {
                Text("Try a different search, or clear the filters.")
            } else {
                Text("The library has no tools yet.")
            }
        } actions: {
            if filter.isFiltering {
                Button("Clear filters") {
                    filter.clearAll()
                }
            }
        }
    }
}

// MARK: - Search

/// The library's search box, shown in the sheet's top bar.
struct ToolSearchField: View {

    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search name or diameter", text: $query)
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Rows

private struct ToolRow: View, Equatable {

    let tool: Tool
    /// Only used for the tooltip; the row itself doesn't show where a tool came from.
    let sourceName: String?

    var body: some View {
        HStack(spacing: 0) {
            ToolTypeIcon(type: tool.type, size: 22)

            Text("Ø\(Self.number(tool.toolDiameter))")
                .font(.body.weight(.medium).monospacedDigit())
                .frame(width: 50, alignment: .leading)

            Spacer().frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            StockPill(quantity: tool.quantity)
                .help(stockHelp)
        }
        .padding(.vertical, 2)
        .help(tool.name)
    }

    /// First line: the type, with "(metal)" after it for tools meant for cutting metal.
    private var title: String {
        tool.isForMetal ? "\(tool.type.displayName) (metal)" : tool.type.displayName
    }

    private var stockHelp: String {
        let stock = "\(tool.quantity) in stock"
        guard let sourceName else { return stock }
        return "\(stock) · \(sourceName)"
    }

    /// Second line: the cutting height, the flutes, then the shank diameter
    /// ("Cut 10 mm · 2 flutes · Shank Ø3.175"). Engraving bits show their tip angle instead of
    /// the cutting height ("TA 30° · Shank Ø3.175"), since the angle is what tells them apart.
    /// Anything the tool doesn't have is left out.
    private var detail: String {
        var parts: [String] = []
        if tool.type == .engraving, let tipAngle = tool.tipAngle, tipAngle > 0 {
            parts.append("TA \(Self.number(tipAngle))°")
        } else if let cuttingHeight = tool.cuttingHeight, cuttingHeight > 0 {
            parts.append("Cut \(Self.number(cuttingHeight)) mm")
        }
        if let flutes = tool.numberOfFlutes, flutes > 0 {
            parts.append(flutes == 1 ? "1 flute" : "\(flutes) flutes")
        }
        if let shank = tool.shankDescription {
            parts.append(shank)
        }
        return parts.joined(separator: " · ")
    }

    private static func number(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

// MARK: - Stock pill

/// Stock count in a capsule at the end of the row. Dimmed when there is none.
private struct StockPill: View {

    let quantity: Int

    var body: some View {
        Text("\(quantity)")
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(quantity == 0 ? .tertiary : .secondary)
            .frame(minWidth: 18)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(quantity == 0 ? 0.08 : 0.15), in: Capsule())
    }
}
