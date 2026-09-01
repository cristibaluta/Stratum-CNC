//
//  StockSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct StockSheet: View {

    var store: StocksStore

    @State private var selectedStockID: StockMaterial.ID?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationSplitView {
            StockListView(
                stocks: store.stocks,
                selectedStockID: $selectedStockID,
                onAdd: addStock
            )
            .navigationSplitViewColumnWidth(200)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        } detail: {
            if let selectedStockID,
               let index = store.stocks.firstIndex(
                    where: { $0.id == selectedStockID }
               ) {

                StockEditorView(
                    stock: Binding(
                        get: {
                            store.stocks[index]
                        },
                        set: { newValue in
                            do {
                                try store.update(newValue)
                            } catch {
                                print("Failed to save stock: \(error)")
                            }
                        }
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
