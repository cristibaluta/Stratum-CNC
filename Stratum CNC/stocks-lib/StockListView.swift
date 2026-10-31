//
//  StockListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct StockListView: View {

    /// Already filtered by the sheet.
    let stocks: [StockMaterial]

    @Binding var selectedStockID: StockMaterial.ID?
    @Binding var filter: StockFilter

    let onDuplicate: (StockMaterial) -> Void
    let onDelete: (StockMaterial) -> Void

    var body: some View {
        List(selection: $selectedStockID) {
            if filter.material == nil {
                // Every material at once: keep the headers so the rows can be told apart.
                ForEach(stocks.groupedByMaterial) { group in
                    Section(group.material.displayName) {
                        rows(group.stocks)
                    }
                }
            } else {
                // One material picked in the rail: it's the only one here, no header needed.
                rows(stocks)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.stockColumnBackground)
        .overlay {
            if stocks.isEmpty {
                emptyState
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .navigationTitle("Stock Library")
    }

    // MARK: Rows

    private func rows(_ stocks: [StockMaterial]) -> some View {
        ForEach(stocks) { stock in
            HStack(spacing: 10) {
                StockPreviewView(geometry: stock.geometry, material: stock.material)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(stock.name)
                    Text(stock.geometry.dimensionsDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("\(stock.quantity)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(stock.quantity == 0 ? .tertiary : .secondary)
            }
            .tag(stock.id)
            .contextMenu {
                Button {
                    onDuplicate(stock)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }

                Divider()

                Button(role: .destructive) {
                    onDelete(stock)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Top bar

    /// Search only. The material and stock filters are in the rail.
    private var topBar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(10)

            Divider()
        }
        .background(Color.stockColumnBackground)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search name, material or size", text: $filter.query)
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
            Label(filter.isFiltering ? "No stock matches" : "No stock here", systemImage: "tray")
        } description: {
            if filter.isFiltering {
                Text("Try a different search, or clear the filters.")
            } else {
                Text("The library has no stock yet.")
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
