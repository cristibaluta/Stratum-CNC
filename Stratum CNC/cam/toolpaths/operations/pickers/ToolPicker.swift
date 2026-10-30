//
//  ToolPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// Chooses the tool. Same look as `OperationPicker` and `DirectionPicker`: a pop-up field
/// that opens a popover on its left, here with two lists of tools drawn with their tip:
/// the last ones used, and the ones in stock (only those meant for metal while the stock
/// material is a metal).
struct ToolPicker: View {

    enum Style {
        /// A labelled inspector row.
        case row
        /// Just the field and the library button, to share a row with other controls.
        case compact
    }

    @Binding var tool: Tool
    var style: Style = .row
    /// The stock being cut. A metal narrows the in-stock list to the tools for metal.
    var stockMaterial: StockMaterialType? = nil
    /// Extra text for the field's help (compact only), e.g. the preset that was just applied.
    var extraHelp: String? = nil
    var onToolPicked: ((Tool) -> Void)?

    @EnvironmentObject var appModel: AppModel

    @State private var showingList = false
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
            Button {
                showingList.toggle()
            } label: {
                InspectorMenuLabel {
                    ToolTypeIcon(type: tool.type, size: 16)
                    Text(tool.displayName)
                }
            }
            .buttonStyle(.plain)
            .help(fieldHelp)
            .popover(isPresented: $showingList, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                ToolListPopover(current: tool,
                                recent: recentTools,
                                inStock: inStockTools,
                                inStockTitle: inStockTitle,
                                inStockEmptyText: inStockEmptyText,
                                onSelect: { candidate in
                                    showingList = false
                                    select(candidate)
                                },
                                onOpenLibrary: {
                                    showingList = false
                                    // Presenting right after dismissing the other popover is dropped
                                    DispatchQueue.main.async { showingLibrary = true }
                                })
            }

            // The whole library, without having to open the list first.
            Button {
                showingLibrary = true
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

    // MARK: Lists

    /// The last 8 tools picked, the newest addition first (persisted in UserDefaults, see `AppModel`).
    private var recentTools: [Tool] {
        appModel.recentTools
    }

    private var metalOnly: Bool {
        stockMaterial?.isMetal ?? false
    }

    /// Every tool in stock; for a metal stock only the ones meant for metal.
    private var inStockTools: [Tool] {
        let order = Dictionary(uniqueKeysWithValues: ToolType.allCases.enumerated().map { ($1, $0) })
        return appModel.toolsStore.tools
            .filter { $0.quantity > 0 && (!metalOnly || $0.isForMetal) }
            .sorted {
                let a = order[$0.type] ?? 0, b = order[$1.type] ?? 0
                return a != b ? a < b : $0.toolDiameter < $1.toolDiameter
            }
    }

    private var inStockTitle: String {
        metalOnly ? "In stock · for metal" : "In stock"
    }

    private var inStockEmptyText: String {
        metalOnly ? "No tools for metal in stock" : "No tools in stock"
    }

    private var fieldHelp: String {
        // The shank and the library's own name for it aren't in the label
        var lines = [tool.displayName]
        if let shank = tool.shankDescription {
            lines.append(shank)
        }
        if !tool.name.isEmpty {
            lines.append(tool.name)
        }
        if style == .compact, let extraHelp {
            lines.append(extraHelp)
        }
        return lines.joined(separator: "\n")
    }

    private func select(_ candidate: Tool) {
        tool = candidate
        appModel.noteToolUsed(candidate)
        onToolPicked?(candidate)
    }
}

// MARK: - Popover

/// The popover content: a section of recent tools and one of tools in stock, each tool a
/// row of tip drawing + size and type + the shank diameter.
private struct ToolListPopover: View {
    let current: Tool
    let recent: [Tool]
    let inStock: [Tool]
    let inStockTitle: String
    let inStockEmptyText: String
    let onSelect: (Tool) -> Void
    let onOpenLibrary: () -> Void

    @State private var hovered: String?

    private let width: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !recent.isEmpty {
                        section("Recent", tools: recent)
                        Divider()
                            .padding(.vertical, 12)
                    }
                    section(inStockTitle, tools: inStock, emptyText: inStockEmptyText)
                }
                .padding(10)
            }
            .frame(maxHeight: 460)

            Divider()
            libraryRow
                .padding(10)
        }
        .frame(width: width)
    }

    private func section(_ title: String, tools: [Tool], emptyText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            if tools.isEmpty, let emptyText {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            ForEach(tools) { tool in
                row(for: tool, in: title)
            }
        }
    }

    private func row(for tool: Tool, in section: String) -> some View {
        let isSelected = tool.id == current.id
        let key = "\(section)-\(tool.id)"

        return Button {
            onSelect(tool)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ToolTypeIcon(type: tool.type, size: 28)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .lineLimit(1)

                    if let shank = tool.shankDescription {
                        Text(shank)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // A recent tool can be out of stock; dimmed like in the library list
                Text("\(tool.quantity)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(tool.quantity == 0 ? .tertiary : .secondary)
                    .help("In stock")

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isSelected: isSelected, isHovered: hovered == key))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? key : (hovered == key ? nil : hovered)
        }
    }

    private var libraryRow: some View {
        Button(action: onOpenLibrary) {
            HStack(spacing: 8) {
                EndMillIcon(size: 14)
                    .foregroundStyle(.secondary)
                Text("Pick from Library…")
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        }
        return isHovered ? Color.primary.opacity(0.06) : Color.clear
    }
}
