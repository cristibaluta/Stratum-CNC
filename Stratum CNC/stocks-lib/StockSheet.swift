//
//  StockSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct StockSheet: View {

    @ObservedObject var store: StocksStore

    /// When set, the sheet shows a "Pick" button. Tapping it returns the selected
    /// stock through this closure and dismisses the sheet. Leave `nil` to browse/edit only.
    var onPick: ((StockMaterial) -> Void)?

    @State private var selectedStockID: StockMaterial.ID?
    @State private var draft: StockMaterial?
    @State private var stockPendingDeletion: StockMaterial?
    @State private var inStockOnly = false

    /// Stocks shown in the list, after applying the in-stock filter.
    private var visibleStocks: [StockMaterial] {
        inStockOnly ? store.stocks.filter { $0.quantity > 0 } : store.stocks
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            NavigationSplitView {
                StockListView(
                    stocks: visibleStocks,
                    selectedStockID: $selectedStockID,
                    inStockOnly: $inStockOnly,
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
            .navigationTitle("Stock Materials")
            .onAppear(perform: selectFirstIfNeeded)
            .onChange(of: selectedStockID) { _ in draft = selectedStock }
            .onChange(of: inStockOnly) { _ in
                let visible = visibleStocks
                if !visible.contains(where: { $0.id == selectedStockID }) {
                    selectedStockID = visible.groupedByMaterial.first?.stocks.first?.id
                }
            }
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
            Divider()
            bottomBar
        }
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

    private var header: some View {
        HStack(spacing: 12) {
            Text("Stock Materials")
                .font(.title2.weight(.semibold))

            Spacer()

            Button {
                addStock()
            } label: {
                Label("Add Stock", systemImage: "plus")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Selects the first item as displayed in the (grouped) list.
    private func selectFirstIfNeeded() {
        guard selectedStockID == nil else { return }
        selectedStockID = visibleStocks.groupedByMaterial.first?.stocks.first?.id
    }

    private func duplicateStock(_ stock: StockMaterial) {
        do {
            let copy = try store.duplicate(stock)
            selectedStockID = copy.id
        } catch {
            print("Failed to duplicate stock: \(error)")
        }
    }

    private func deleteStock(_ stock: StockMaterial) {
        // Pick the neighbour in the displayed (grouped) order before deleting.
        let ordered = visibleStocks.groupedByMaterial.flatMap(\.stocks)
        let position = ordered.firstIndex(where: { $0.id == stock.id })

        do {
            try store.delete(stock)
        } catch {
            print("Failed to delete stock: \(error)")
            return
        }

        guard selectedStockID == stock.id else { return }
        let remaining = visibleStocks.groupedByMaterial.flatMap(\.stocks)
        if let position, !remaining.isEmpty {
            selectedStockID = remaining[min(position, remaining.count - 1)].id
        } else {
            selectedStockID = nil
        }
    }

    private func addStock() {
        let stock = StockMaterial(
            name: "New Stock",
            material: .aluminum,
            geometry: .rectangular(width: 100, height: 50, depth: 10)
        )

        do {
            try store.add(stock)

            // Automatically select the newly created stock.
            selectedStockID = stock.id
        } catch {
            print("Failed to add stock: \(error)")
        }
    }
}
