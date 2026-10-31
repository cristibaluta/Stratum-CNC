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

    /// Every source (bundled, custom, imports) and, per source id, how many tools it would show now.
    let sources: [ToolSourceInfo]
    let sourceCounts: [UUID: Int]

    let importHelp: String
    let onAdd: () -> Void
    let onImport: () -> Void
    let onManageImports: () -> Void
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
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .navigationTitle("Tool Library")
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                searchField

                HStack(spacing: 6) {
                    ForEach(MaterialFilter.allCases, id: \.self) { material in
                        FilterChip(
                            title: material.chipTitle,
                            isSelected: filter.material == material
                        ) {
                            filter.material = material
                        }
                    }
                    Spacer(minLength: 0)
                }
                .help("Metal is a guess from each tool's presets, name and group")

                HStack(spacing: 8) {
                    sourceMenu
                    addMenu
                }
            }
            .padding(10)

            Divider()
        }
        .background(Color.toolColumnBackground)
    }

    /// Source dropdown: All sources, one entry per source with its count, then Manage imports….
    private var sourceMenu: some View {
        Menu {
            Picker("Source", selection: $filter.source) {
                Text("All sources (\(sourceCounts.values.reduce(0, +)))")
                    .tag(ToolSourceFilter.any)
                ForEach(sources) { source in
                    Text("\(source.name) (\(sourceCounts[source.id, default: 0]))")
                        .tag(ToolSourceFilter.source(source.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button("Manage imports…", action: onManageImports)
        } label: {
            Text(sourceTitle)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Show only tools from one source")
    }

    private var sourceTitle: String {
        switch filter.source {
            case .any: "All sources"
            case .source(let id): sources.first { $0.id == id }?.name ?? "All sources"
        }
    }

    private var addMenu: some View {
        Menu {
            Button(action: onAdd) {
                Label("Add Tool", systemImage: "plus")
            }
            Button(action: onImport) {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .help(importHelp)
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add or import tools")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search name or diameter", text: $filter.query)
                .textFieldStyle(.plain)

            if !filter.query.isEmpty {
                Button {
                    filter.query = ""
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

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(filter.hasRefinements ? "No tools match" : "No tools here", systemImage: "tray")
        } description: {
            if filter.hasRefinements {
                Text("Try a different search, or clear the filters.")
            } else if filter.scope == .inStock {
                Text("Nothing is in stock yet.")
            } else {
                Text("There are no tools in this category.")
            }
        } actions: {
            if filter.hasRefinements {
                Button("Clear filters") {
                    filter.clearRefinements()
                }
            }
        }
    }
}

// MARK: - Rows

private struct ToolRow: View {

    let tool: Tool
    /// Only used for the tooltip; the row itself doesn't show where a tool came from.
    let sourceName: String?

    var body: some View {
        HStack(spacing: 10) {
            ToolTypeIcon(type: tool.type, size: 22)

            Text("Ø\(Self.number(tool.toolDiameter))")
                .font(.body.weight(.medium).monospacedDigit())
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.type.displayName)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StockPill(quantity: tool.quantity)
                .help(stockHelp)
        }
        .padding(.vertical, 2)
        .help(tool.name)
    }

    private var stockHelp: String {
        let stock = "\(tool.quantity) in stock"
        guard let sourceName else { return stock }
        return "\(stock) · \(sourceName)"
    }

    /// Second line: the length, then the shank diameter ("L 10 mm · Shank Ø3.175").
    /// Either is left out when the tool doesn't have it.
    private var detail: String {
        var parts: [String] = []
        if let length = tool.length, length > 0 {
            parts.append("L \(Self.number(length)) mm")
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

// MARK: - Chips

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

private struct FilterChip: View {

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.35),
                        lineWidth: 0.5
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension MaterialFilter {

    /// Short labels so the three chips fit the narrowest list column (260 pt).
    var chipTitle: String {
        switch self {
            case .any: "Any"
            case .metal: "Metal"
            case .nonMetal: "Non metal"
        }
    }
}
