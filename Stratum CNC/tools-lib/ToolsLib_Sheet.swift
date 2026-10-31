//
//  ToolsSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ToolsLib_Sheet: View {

    @ObservedObject var store: ToolsStore

    /// When set, the sheet shows a "Pick" button. Tapping it returns the selected
    /// tool through this closure and dismisses the sheet. Leave `nil` to browse/edit only.
    var onPick: ((Tool) -> Void)?
    @State private var selectedToolID: Tool.ID?
    @State private var toolPendingDeletion: Tool?
    /// The filters live in the store, so they are still there when the sheet is reopened.
    private var filter: ToolFilter {
        get { store.filter }
        nonmutating set { store.filter = newValue }
    }
    @State private var isImporting = false
    @State private var isManagingImports = false
    @State private var importMessage: String?

    /// Tools shown in the list: filtered by the rail and the other filters, and sorted.
    private var visibleTools: [Tool] {
        filter.apply(to: store.tools)
    }

    /// Types that have at least one tool in the library, in rail order.
    private var presentTypes: [ToolType] {
        let present = Set(store.tools.map(\.type))
        return ToolType.allCases.filter { present.contains($0) }
    }

    @Environment(\.dismiss) private var dismiss

    /// Type rail on the far left. Added on top of the previous 900 pt minimum so the editor
    /// column keeps the ~600 pt it had before the rail existed.
    private static let railWidth: CGFloat = 170
    private static let minSheetWidth: CGFloat = 1080
    /// Fixed: the sheet only grows sideways. Includes the title bar and the bottom bar.
    private static let sheetHeight: CGFloat = 640

    private static let importDialogMessage = "Fusion 360 tools library (.tools, .zip, .json)"

    private static let importHelp = "Import tools from a Fusion 360 tool library (.tools, or a .zip / .json export). Cutting tools such as end mills, drills and V-bits are added; holders and taps are ignored, and tools already in the library are skipped."

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                ToolTypeRail(
                    filter: $store.filter,
                    types: presentTypes,
                    shanks: ToolFilter.shankSizes(in: store.tools),
                    counts: filter.facetCounts(in: store.tools),
                    sources: store.sources,
                    sourceCounts: filter.sourceCounts(in: store.tools),
                    importHelp: Self.importHelp,
                    onAdd: addTool,
                    onImport: { isImporting = true },
                    onManageImports: { isManagingImports = true }
                )
                .frame(width: Self.railWidth)
                Divider()
                NavigationSplitView {
                    ToolListView(
                        tools: visibleTools,
                        selectedToolID: $selectedToolID,
                        filter: $store.filter,
                        sources: store.sources,
                        onDuplicate: duplicateTool,
                        onDelete: { toolPendingDeletion = $0 }
                    )
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
                } detail: {
                    if let selectedToolID,
                       let current = store.tools.first(where: { $0.id == selectedToolID }) {
                        // Bound by id, not by index: when tools are removed (a deleted import
                        // batch, Revert) SwiftUI can still call these closures once before the
                        // view is rebuilt, and a captured index would then be out of range.
                        ToolEditorView(
                            tool: Binding(
                                get: { store.tools.first(where: { $0.id == selectedToolID }) ?? current },
                                set: { newValue in
                                    if let index = store.tools.firstIndex(where: { $0.id == selectedToolID }) {
                                        store.tools[index] = newValue
                                    }
                                }
                            ),
                            source: store.source(for: current)
                        )
                    } else {
                        ContentUnavailableView(
                            "No Tool Selected",
                            systemImage: "wrench.and.screwdriver",
                            description: Text("Select a tool from the list.")
                        )
                    }
                }
                .navigationTitle("Tools")
                .onAppear(perform: selectFirstIfNeeded)
                .onChange(of: store.filter) { _ in reselectIfHidden() }
                // Removing an import batch (or reverting that) changes which tools exist.
                .onChange(of: store.tools.map(\.id)) { _ in reselectIfHidden() }
                // A source filter must not outlive its source.
                .onChange(of: store.sources) { _ in resetSourceFilterIfMissing() }
                .confirmationDialog(
                    "Delete \"\(toolPendingDeletion?.name ?? "")\"?",
                    isPresented: Binding(
                        get: { toolPendingDeletion != nil },
                        set: { if !$0 { toolPendingDeletion = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: toolPendingDeletion
                ) { tool in
                    Button("Delete", role: .destructive) {
                        deleteTool(tool)
                    }
                } message: { _ in
                    Text("This can't be undone.")
                }
            }
            Divider()
            bottomBar
        }
        .background(Color.stockColumnBackground)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "tools") ?? .data, .zip, .json]
        ) { result in
            handleImport(result)
        }
        .fileDialogMessage(Self.importDialogMessage)
        .fileDialogConfirmationLabel("Import")
        .sheet(isPresented: $isManagingImports) {
            ManageImportsView(store: store)
        }
        .alert("Import Tools", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        // The sheet owns its minimum size so the editor column keeps its width:
        // rail + list (ideal 300) + editor (>= 600) = 1080.
        .frame(minWidth: Self.minSheetWidth, minHeight: Self.sheetHeight, maxHeight: Self.sheetHeight)
    }

    private var selectedTool: Tool? {
        store.tools.first { $0.id == selectedToolID }
    }

    /// Title bar: what the sheet is for, and how many tools the library holds.
    private var titleBar: some View {
        HStack(spacing: 12) {
            Text(onPick == nil ? "Tool Library" : "Pick a Tool")
                .font(.headline)
            Spacer()
            Text(store.tools.count == 1 ? "1 tool" : "\(store.tools.count) tools")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Permanent bar: Revert/Save while there are unsaved edits, otherwise Done (or Pick).
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if store.hasUnsavedChanges {
                Text("Unsaved changes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.hasUnsavedChanges {
                Button("Revert") {
                    store.revertChanges()
                }
                Button("Save") {
                    do {
                        try store.save()
                    } catch {
                        print("Failed to save tools: \(error)")
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
            } else if let onPick {
                Button("Pick") {
                    if let tool = selectedTool {
                        onPick(tool)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedTool == nil)
            } else {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let imported = try FusionToolsImporter.importTools(from: url)
            let counts = try store.importTools(imported.tools, fileName: url.lastPathComponent)

            var message = "Imported \(counts.added) tools"
            if let batch = counts.batch {
                message += " from \(batch.name)"
            }
            message += "."
            if counts.updated > 0 {
                message += " Added presets to \(counts.updated) existing tools."
            }
            if counts.skipped > 0 {
                message += " \(counts.skipped) already in the library were skipped."
            }
            if imported.unsupportedCount > 0 {
                message += " \(imported.unsupportedCount) unsupported entries (holders, taps, …) were ignored."
            }
            importMessage = message
        } catch {
            importMessage = error.localizedDescription
        }
    }

    /// Keeps the selection on something visible after a filter changes.
    private func reselectIfHidden() {
        let visible = visibleTools
        if !visible.contains(where: { $0.id == selectedToolID }) {
            selectedToolID = visible.first?.id
        }
    }

    /// If the source being filtered on is gone (its batch was removed), go back to all sources.
    private func resetSourceFilterIfMissing() {
        guard case .source(let id) = filter.source,
              !store.sources.contains(where: { $0.id == id }) else { return }
        filter.source = .any
    }

    /// Selects the first item as displayed in the list.
    private func selectFirstIfNeeded() {
        guard selectedToolID == nil else { return }
        selectedToolID = visibleTools.first?.id
    }

    /// After adding or duplicating, make sure the new tool isn't hidden by the current filters
    /// (a new tool has no stock, and its name may not match the search).
    private func ensureVisible(_ id: Tool.ID) {
        func isVisible() -> Bool { visibleTools.contains { $0.id == id } }
        if isVisible() { return }
        // Widen step by step: search/material/source, then stock (a new tool has none),
        // then the type and shank selections.
        filter.clearRefinements()
        if isVisible() { return }
        filter.stockOnly = false
        if isVisible() { return }
        filter.clearAll()
    }

    private func duplicateTool(_ tool: Tool) {
        do {
            let copy = try store.duplicate(tool)
            ensureVisible(copy.id)
            selectedToolID = copy.id
        } catch {
            print("Failed to duplicate tool: \(error)")
        }
    }

    private func deleteTool(_ tool: Tool) {
        // Pick the neighbour in the displayed order before deleting.
        let ordered = visibleTools
        let position = ordered.firstIndex(where: { $0.id == tool.id })

        do {
            try store.delete(tool)
        } catch {
            print("Failed to delete tool: \(error)")
            return
        }

        guard selectedToolID == tool.id else { return }
        let remaining = visibleTools
        if let position, !remaining.isEmpty {
            selectedToolID = remaining[min(position, remaining.count - 1)].id
        } else {
            selectedToolID = nil
        }
    }

    private func addTool() {
        // The new tool takes the type and shank size selected in the rail, else the type of
        // the selected tool and a 3.175 mm shank.
        let current = store.tools.first(where: { $0.id == selectedToolID })
        let tool = Tool(
            name: "New Tool",
            shankDiameter: filter.shank ?? 3.175,
            toolDiameter: 1,
            length: 10,
            type: filter.type ?? current?.type ?? .endMill
        )

        do {
            try store.add(tool)
            ensureVisible(tool.id)
            selectedToolID = tool.id
        } catch {
            print("Failed to add tool: \(error)")
        }
    }
}
