//
//  MaterialPanelView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 29.08.2026.
//

import SwiftUI

struct PanelStockMaterial: View {

    @Binding var stock: StockMaterial
    @Binding var isStockVisible: Bool
    let isCompact: Bool
    var onOpenStocksLib: (() async -> StockMaterial?)?
    /// When set, the library button opens the stocks library in a popover instead of calling `onOpenStocksLib`.
    var stocksStore: StocksStore? = nil
    /// Why the setup can't be cut from this stock (a side face needs a rectangular block).
    var warning: String? = nil
    @State private var showingLibrary = false

    /// Part of a bigger panel (the setup's details): no frame and padding of its own.
    var isEmbedded = false
    /// Whether the details are open when the panel appears.
    var startsExpanded = false

    /// Collapsed, the panel is one line. Clicking it opens the editable details.
    @State private var isExpanded = false

    var body: some View {
        if isEmbedded {
            content
        } else {
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .canvasChrome()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryLine
            if let warning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 6)
            }
            if isExpanded {
                details
                    .padding(.top, 10)
            }
        }
        .onAppear {
            isExpanded = startsExpanded
        }
    }

    // MARK: Summary

    /// Visibility, library, then "Material · Shape · size" -- all on one line.
    private var summaryLine: some View {
        HStack(spacing: 8) {
            if !isCompact {
                visibilityButton
            }

            Button {
                if stocksStore != nil {
                    showingLibrary = true
                    return
                }
                Task {
                    if let returnedItem = await onOpenStocksLib?() {
                        self.stock = returnedItem
                    } else {
                        print("No object selected")
                    }
                }
            } label: {
                Image(systemName: "cube")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Pick from the material library")
            .popover(isPresented: $showingLibrary, arrowEdge: .leading) {
                if let stocksStore {
                    StocksLib_Sheet(store: stocksStore, onPick: { stock = $0 })
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(summary)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    InspectorChevron(isExpanded: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide material details" : "Edit material")
        }
    }

    private var summary: String {
        "\(stock.material.displayName) · \(stock.geometry.displayName) · \(sizeText)"
    }

    private var sizeText: String {
        switch stock.geometry {
            case .rectangular(let length, let width, let height):
                return "\(format(length))×\(format(width))×\(format(height)) mm"
            case .cylindrical(let diameter, let length):
                return "Ø\(format(diameter))×\(format(length)) mm"
            case .disk(let outerDiameter, let innerDiameter, let height):
                return "Ø\(format(outerDiameter))/\(format(innerDiameter))×\(format(height)) mm"
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            Divider()
                .padding(.bottom, 2)

            StockMaterialForm(stock: $stock)
        }
    }

    private var visibilityButton: some View {
        Button {
            isStockVisible.toggle()
        } label: {
            Image(systemName: isStockVisible ? "eye" : "eye.slash")
                .font(.system(size: 12))
                .foregroundStyle(isStockVisible ? .primary : .secondary)
                .frame(width: 18)
        }
        .buttonStyle(.borderless)
        .help(isStockVisible ? "Hide material in 2D" : "Show material in 2D")
    }
}
