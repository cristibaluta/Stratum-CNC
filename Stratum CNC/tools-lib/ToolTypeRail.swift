//
//  ToolTypeRail.swift
//  Stratum CNC
//
//  Far-left column of the tool library. Three sections (All tools / In stock, Type, Shank),
//  each with its own selection: at most one row per section, and the sections combine.
//  Click a selected row again to deselect it. Counts come from `ToolFilter.facetCounts(in:)`.
//  The footer holds the material and source filters and the Add / Import buttons.
//

import SwiftUI
import AppKit

extension Color {

    /// One background for the rail and the tool list, so they match the editor column
    /// instead of taking the translucent gray sidebar material. If the editor's white ever
    /// differs from this, change it here and both columns follow.
    static var toolColumnBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

struct ToolTypeRail: View {

    @Binding var filter: ToolFilter

    /// Types and shank sizes that exist in the library, in the order to show them.
    let types: [ToolType]
    let shanks: [Double]

    /// Faceted counts. A missing entry means zero.
    let counts: ToolFilter.FacetCounts

    /// Every source and, per source id, how many tools it would show now.
    let sources: [ToolSourceInfo]
    let sourceCounts: [UUID: Int]

    let importHelp: String
    let onAdd: () -> Void
    let onImport: () -> Void
    let onManageImports: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider()
            footer
        }
        .background(Color.toolColumnBackground)
    }

    private var list: some View {
        List {
            row("All tools", count: counts.all, isSelected: !filter.stockOnly) {
                filter.stockOnly = false
            } icon: {
                Image(systemName: "square.grid.2x2")
            }
            row("In stock", count: counts.inStock, isSelected: filter.stockOnly) {
                filter.stockOnly.toggle()
            } icon: {
                Image(systemName: "shippingbox")
            }

            Section("Type") {
                ForEach(types, id: \.self) { type in
                    row(type.displayName,
                        count: counts.types[type, default: 0],
                        isSelected: filter.type == type) {
                            filter.type = filter.type == type ? nil : type
                        } icon: {
                            ToolTypeIcon(type: type, size: 18)
                        }
                }
            }.padding(0).frame(width: .infinity).background(Color.red)

            if !shanks.isEmpty {
                Section("Shank") {
                    ForEach(shanks, id: \.self) { size in
                        let isSelected = filter.shank.map {
                            ToolFilter.shankKey($0) == ToolFilter.shankKey(size)
                        } ?? false
                        row("\(Self.number(size)) mm",
                            count: counts.shanks[ToolFilter.shankKey(size), default: 0],
                            isSelected: isSelected) {
                                filter.shank = isSelected ? nil : size
                            } icon: {
                                Image(systemName: "circle.dashed")
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.orange)
    }

    private static func number(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private func row<Icon: View>(_ title: String,
                                 count: Int,
                                 isSelected: Bool,
                                 action: @escaping () -> Void,
                                 @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon()
                    .frame(width: 18, height: 18)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A row with nothing under the current filters stays clickable, just quieter.
        .opacity(count == 0 && !isSelected ? 0.5 : 1)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Footer

    /// Filters and actions, always visible at the bottom of the rail.
    private var footer: some View {
        VStack(spacing: 8) {
            materialMenu
            sourceMenu

            HStack(spacing: 6) {
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .help("Add a new tool")

                Button(action: onImport) {
                    Label("Import…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .help(importHelp)
            }
            .controlSize(.small)
        }
        .padding(10)
    }

    private var materialMenu: some View {
        Menu {
            Picker("Material", selection: $filter.material) {
                ForEach(MaterialFilter.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(filter.material.title)
                .lineLimit(1)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Metal is a guess from each tool's presets, name and group")
    }

    /// All sources, one entry per source with its count, then Manage imports….
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
}

#Preview {
    ToolTypeRail(
        filter: .constant(ToolFilter()),
        types: [.endMill, .ballNose, .engraving, .drill, .corn, .chamfer],
        shanks: [3.175, 4, 6, 6.35],
        counts: ToolFilter.FacetCounts(
            all: 69, inStock: 4,
            types: [.endMill: 13, .ballNose: 8, .engraving: 11, .drill: 25, .corn: 11],
            shanks: [3175: 40, 4000: 9, 6000: 12, 6350: 8]
        ),
        sources: [.bundled, .custom],
        sourceCounts: [ToolSourceInfo.bundledID: 69],
        importHelp: "",
        onAdd: {},
        onImport: {},
        onManageImports: {}
    )
    .frame(width: 170, height: 560)
}
