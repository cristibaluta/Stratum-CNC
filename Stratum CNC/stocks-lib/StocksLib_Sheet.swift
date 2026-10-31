//
//  StockSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct StocksLib_Sheet: View {

    @ObservedObject var store: StocksStore

    /// When set, the sheet shows a "Pick" button. Tapping it returns the selected
    /// stock through this closure and dismisses the sheet. Leave `nil` to browse/edit only.
    var onPick: ((StockMaterial) -> Void)?

    @State private var selectedStockID: StockMaterial.ID?
    @State private var draft: StockMaterial?
    @State private var stockPendingDeletion: StockMaterial?

    /// Stocks shown in the list: filtered by the rail and the search, in material order.
    private var visibleStocks: [StockMaterial] {
        store.filter.apply(to: store.stocks)
    }

    /// Materials that have at least one stock in the library, in rail order.
    private var presentMaterials: [StockMaterialType] {
        let present = Set(store.stocks.map(\.material))
        return StockMaterialType.allCases.filter { present.contains($0) }
    }

    @Environment(\.dismiss) private var dismiss

    /// Material rail on the far left. Same sizes as the tool library, so the two sheets match.
    private static let railWidth: CGFloat = 170
    private static let minSheetWidth: CGFloat = 960
    /// Fixed: the sheet only grows sideways. Includes the title bar and the bottom bar.
    private static let sheetHeight: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                StockMaterialRail(
                    filter: $store.filter,
                    materials: presentMaterials,
                    counts: store.filter.facetCounts(in: store.stocks),
                    onAdd: addStock
                )
                .frame(width: Self.railWidth)
                Divider()
                NavigationSplitView {
                    StockListView(
                        stocks: visibleStocks,
                        selectedStockID: $selectedStockID,
                        filter: $store.filter,
                        onDuplicate: duplicateStock,
                        onDelete: { stockPendingDeletion = $0 }
                    )
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
                } detail: {
                    if let selectedStockID,
                       store.stocks.contains(where: { $0.id == selectedStockID }),
                       draft?.id == selectedStockID {

                        StockEditorView(
                            draft: Binding(
                                get: { draft ?? store.stocks.first { $0.id == selectedStockID }! },
                                set: { draft = $0 }
                            )
                        )

                    } else {
                        ContentUnavailableView(
                            "No Stock Selected",
                            systemImage: "cube",
                            description: Text("Select a stock material from the list.")
                        )
                    }
                }
                .background(Color.stockColumnBackground)
                .navigationTitle("Stock Materials")
                .onAppear(perform: selectFirstIfNeeded)
                .onChange(of: selectedStockID) { _ in draft = selectedStock }
                .onChange(of: store.filter) { _ in reselectIfHidden() }
                .confirmationDialog(
                    "Delete \"\(stockPendingDeletion?.name ?? "")\"?",
                    isPresented: Binding(
                        get: { stockPendingDeletion != nil },
                        set: { if !$0 { stockPendingDeletion = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: stockPendingDeletion
                ) { stock in
                    Button("Delete", role: .destructive) {
                        deleteStock(stock)
                    }
                } message: { _ in
                    Text("This can't be undone.")
                }
            }
            Divider()
            bottomBar
        }
        .background(Color.stockColumnBackground)
        // The sheet owns its minimum size so the editor column keeps its width:
        // rail + list (ideal 300) + editor (>= 600) = 1080.
        .frame(minWidth: Self.minSheetWidth, minHeight: Self.sheetHeight, maxHeight: Self.sheetHeight)
    }

    private var selectedStock: StockMaterial? {
        store.stocks.first { $0.id == selectedStockID }
    }

    private var hasUnsavedChanges: Bool {
        guard let draft, let selectedStock else { return false }
        return draft != selectedStock
    }

    /// Permanent bar: Revert/Save while there are unsaved edits, otherwise Done (or Pick).
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if hasUnsavedChanges {
                Text("Unsaved changes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if hasUnsavedChanges {
                Button("Revert") {
                    draft = selectedStock
                }
                Button("Save") {
                    guard let draft else { return }
                    do {
                        try store.update(draft)
                    } catch {
                        print("Failed to save stock: \(error)")
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
            } else if let onPick {
                Button("Pick") {
                    if let stock = selectedStock {
                        onPick(stock)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedStock == nil)
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

    /// Title bar: what the sheet is for, and how many stocks the library holds.
    private var titleBar: some View {
        HStack(spacing: 12) {
            Text(onPick == nil ? "Stock Library" : "Pick a Stock")
                .font(.headline)
            Spacer()
            Text(store.stocks.count == 1 ? "1 stock" : "\(store.stocks.count) stocks")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Keeps the selection on something visible after a filter changes.
    private func reselectIfHidden() {
        let visible = visibleStocks
        if !visible.contains(where: { $0.id == selectedStockID }) {
            selectedStockID = visible.first?.id
        }
    }

    /// Selects the first item as displayed in the list.
    private func selectFirstIfNeeded() {
        guard selectedStockID == nil else { return }
        selectedStockID = visibleStocks.first?.id
    }

    /// After adding or duplicating, make sure the new stock isn't hidden by the current filters
    /// (a new stock has no quantity, and its name may not match the search).
    private func ensureVisible(_ id: StockMaterial.ID) {
        func isVisible() -> Bool { visibleStocks.contains { $0.id == id } }
        if isVisible() { return }
        // Widen step by step: the search, then "In stock" (a new stock has none),
        // then the material selection.
        store.filter.clearRefinements()
        if isVisible() { return }
        store.filter.stockOnly = false
        if isVisible() { return }
        store.filter.clearAll()
    }

    private func duplicateStock(_ stock: StockMaterial) {
        do {
            let copy = try store.duplicate(stock)
            ensureVisible(copy.id)
            selectedStockID = copy.id
        } catch {
            print("Failed to duplicate stock: \(error)")
        }
    }

    private func deleteStock(_ stock: StockMaterial) {
        // Pick the neighbour in the displayed order before deleting.
        let ordered = visibleStocks
        let position = ordered.firstIndex(where: { $0.id == stock.id })

        do {
            try store.delete(stock)
        } catch {
            print("Failed to delete stock: \(error)")
            return
        }

        guard selectedStockID == stock.id else { return }
        let remaining = visibleStocks
        if let position, !remaining.isEmpty {
            selectedStockID = remaining[min(position, remaining.count - 1)].id
        } else {
            selectedStockID = nil
        }
    }

    private func addStock() {
        // The new stock takes the material selected in the rail, else the material of the
        // selected stock.
        let material = store.filter.material ?? selectedStock?.material ?? .aluminum
        let stock = StockMaterial(
            name: "New Stock",
            material: material,
            geometry: .rectangular(width: 100, height: 50, depth: 10)
        )

        do {
            try store.add(stock)
            ensureVisible(stock.id)

            // Automatically select the newly created stock.
            selectedStockID = stock.id
        } catch {
            print("Failed to add stock: \(error)")
        }
    }
}
