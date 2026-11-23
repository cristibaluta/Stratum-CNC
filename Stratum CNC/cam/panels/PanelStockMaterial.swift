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
    /// Which stock this panel edits, as a small tag in the summary: "Project stock" (shared by every
    /// setup without a stock of its own) or "This setup only". Nil hides it (nothing to confuse).
    var scopeTag: String? = nil
    /// Set while the stock belongs to one setup: the details then offer "Use project stock".
    var onUseProjectStock: (() -> Void)? = nil
    /// Set while the setup uses the project's stock and there are other setups: the details then
    /// offer "Use own stock", which starts from a copy of the project's.
    var onUseOwnStock: (() -> Void)? = nil
    /// Why the setup can't be cut from this stock (a side face needs a rectangular block).
    var warning: String? = nil
    /// A new value opens the details: a setup on a different stock was just added, and its stock
    /// is the first thing to set.
    var expandTrigger: UUID? = nil

    @State private var showingLibrary = false

    /// Collapsed, the panel is one line. Clicking it opens the editable details.
    @State private var isExpanded = false

    var body: some View {
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
        .onChange(of: expandTrigger) { _ in
            if expandTrigger != nil {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded = true
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
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
                    if let scopeTag {
                        Text(scopeTag)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                            .fixedSize()
                    }
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

            if let onUseProjectStock {
                HStack(spacing: 8) {
                    Text("Only this setup is cut from this stock.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Use project stock", action: onUseProjectStock)
                        .controlSize(.small)
                        .help("Drop this setup's own stock and cut it from the project's again")
                }
            }

            if let onUseOwnStock {
                HStack(spacing: 8) {
                    Text("Shared by every setup without its own stock.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Use own stock", action: onUseOwnStock)
                        .controlSize(.small)
                        .help("Cut only this setup from another stock, starting as a copy of the project's")
                }
            }

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
