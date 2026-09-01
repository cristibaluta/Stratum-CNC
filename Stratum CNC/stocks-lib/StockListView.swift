//
//  StockListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct StockListView: View {

    let stocks: [StockMaterial]
    @Binding var selectedStockID: StockMaterial.ID?
    let onAdd: () -> Void

    var body: some View {
        List(stocks, selection: $selectedStockID) { stock in

            VStack(alignment: .leading, spacing: 3) {
                Text(stock.name)
                Text("\(stock.geometry.displayName) · " + stock.geometry.dimensionsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(stock.id)
        }
        .navigationTitle("Stock Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onAdd()
                } label: {
                    Label("Add Stock", systemImage: "plus")
                }
            }
        }
    }
}
