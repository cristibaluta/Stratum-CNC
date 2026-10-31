//
//  StockFilter.swift
//  Stratum CNC
//
//  Pure filtering and counting for the stock library. No SwiftUI, no store:
//  the views hold a `StockFilter` as state and call `apply(to:)` / `facetCounts(in:)`.
//

import Foundation

struct StockFilter: Equatable {

    // The rail has two sections. Each contributes at most one selection and they combine
    // (all must match): stock (All stocks / In stock) and one material.

    /// "In stock" is selected. `false` is the "All stocks" row.
    var stockOnly: Bool = false
    var material: StockMaterialType?
    var query: String = ""

    // MARK: Refinements

    /// True when something in the rail narrows the list.
    var hasRailSelection: Bool {
        stockOnly || material != nil
    }

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when anything at all narrows the list. Drives the empty state.
    var isFiltering: Bool {
        hasRailSelection || hasQuery
    }

    /// Resets the search. The rail selection is left alone.
    mutating func clearRefinements() {
        query = ""
    }

    /// Resets everything: the rail selection and the search.
    mutating func clearAll() {
        clearRefinements()
        stockOnly = false
        material = nil
    }

    // MARK: Apply

    /// The stocks to show, in material order (`StockMaterialType.allCases`), largest first
    /// inside a material. Same order as `groupedByMaterial`, so flattening the groups matches.
    func apply(to stocks: [StockMaterial]) -> [StockMaterial] {
        stocks
            .filter { matches($0) }
            .groupedByMaterial
            .flatMap(\.stocks)
    }

    // MARK: Counts

    /// Counts for the rail. Faceted per section: each count respects every selection and the
    /// search except its own section's, so a row shows how many stocks the list would have
    /// if that row were the selection of its section.
    struct FacetCounts {
        /// "All stocks" and "In stock" rows.
        var all = 0
        var inStock = 0
        var materials: [StockMaterialType: Int] = [:]
    }

    func facetCounts(in stocks: [StockMaterial]) -> FacetCounts {
        var result = FacetCounts()
        for stock in stocks {
            if matches(stock, ignoring: .stock) {
                result.all += 1
                if stock.quantity > 0 { result.inStock += 1 }
            }
            if matches(stock, ignoring: .material) {
                result.materials[stock.material, default: 0] += 1
            }
        }
        return result
    }

    // MARK: Matching

    private enum Facet {
        case stock, material
    }

    /// All facets must match. `ignoring` skips one, for the faceted counts.
    private func matches(_ stock: StockMaterial, ignoring ignored: Facet? = nil) -> Bool {
        (ignored == .stock || !stockOnly || stock.quantity > 0)
            && (ignored == .material || material == nil || stock.material == material)
            && matchesQuery(stock)
    }

    /// Every word typed must appear somewhere in the stock's name, material or size.
    /// Case-insensitive, any order: "alu 100" finds "6061 Aluminum Sheet Plate" (100 × 150 × 3).
    private func matchesQuery(_ stock: StockMaterial) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }

        let haystack = [
            stock.name,
            stock.material.displayName,
            stock.geometry.dimensionsDescription
        ]
        .joined(separator: " ")
        .lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}
