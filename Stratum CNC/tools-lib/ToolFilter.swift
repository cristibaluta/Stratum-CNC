//
//  ToolScope.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 31.10.2026.
//
//  Pure filtering, sorting and counting for the tool library. No SwiftUI, no store:
//  the views hold a `ToolFilter` as state and call `apply(to:)` / `counts(in:)`.
//

import Foundation

/// The Any / Metal / Non metal chips.
enum MaterialFilter: CaseIterable, Hashable {
    case any
    case metal
    case nonMetal

    var title: String {
        switch self {
            case .any: "Any material"
            case .metal: "Metal"
            case .nonMetal: "Non metal"
        }
    }
}

/// The Source dropdown: every source, or one specific source (a bundled, custom or import batch id).
enum ToolSourceFilter: Hashable {
    case any
    case source(UUID)
}

struct ToolFilter: Equatable {

    // The rail has three sections. Each contributes at most one selection and they combine
    // (all must match): stock (All tools / In stock), one type, one shank size.

    /// "In stock" is selected. `false` is the "All tools" row.
    var stockOnly: Bool = false
    var type: ToolType?
    /// Shank diameter in mm.
    var shank: Double?

    var material: MaterialFilter = .any
    var source: ToolSourceFilter = .any
    var query: String = ""

    // MARK: Refinements

    /// True when something in the rail narrows the list.
    var hasRailSelection: Bool {
        stockOnly || type != nil || shank != nil
    }

    /// True when search, material or source narrow the list.
    var hasRefinements: Bool {
        material != .any
            || source != .any
            || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when anything at all narrows the list. Drives the empty state.
    var isFiltering: Bool {
        hasRailSelection || hasRefinements
    }

    /// Resets search, material and source. The rail selection is left alone.
    mutating func clearRefinements() {
        material = .any
        source = .any
        query = ""
    }

    /// Resets everything: the rail selection and the refinements.
    mutating func clearAll() {
        clearRefinements()
        stockOnly = false
        type = nil
        shank = nil
    }

    // MARK: Apply

    /// The tools to show: filtered by every facet, then sorted.
    func apply(to tools: [Tool]) -> [Tool] {
        tools
            .filter { matches($0) }
            .sorted(by: Self.areInOrder)
    }

    // MARK: Counts

    /// Counts for the rail. Faceted per section: each count respects every selection and
    /// refinement except its own section's, so a row shows how many tools the list would
    /// have if that row were the selection of its section.
    struct FacetCounts {
        /// "All tools" and "In stock" rows.
        var all = 0
        var inStock = 0
        var types: [ToolType: Int] = [:]
        /// Keyed by `ToolFilter.shankKey(_:)`.
        var shanks: [Int: Int] = [:]
    }

    func facetCounts(in tools: [Tool]) -> FacetCounts {
        var result = FacetCounts()
        for tool in tools {
            if matches(tool, ignoring: .stock) {
                result.all += 1
                if tool.quantity > 0 { result.inStock += 1 }
            }
            if matches(tool, ignoring: .type) {
                result.types[tool.type, default: 0] += 1
            }
            if matches(tool, ignoring: .shank) {
                result.shanks[Self.shankKey(tool.shankDiameter), default: 0] += 1
            }
        }
        return result
    }

    /// Counts for the Source dropdown, keyed by source id. Faceted like the rail: they respect
    /// everything except the source filter itself. Missing entry means zero.
    func sourceCounts(in tools: [Tool]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for tool in tools where matches(tool, ignoring: .source) {
            result[tool.sourceID, default: 0] += 1
        }
        return result
    }

    // MARK: Shank sizes

    /// Shank diameters compare to the thousandth of a mm, so 3.175 read from two files is one size.
    static func shankKey(_ value: Double) -> Int {
        Int((value * 1000).rounded())
    }

    /// The distinct known shank sizes in the library, smallest first. A shank of 0 means
    /// "not known" and gets no row.
    static func shankSizes(in tools: [Tool]) -> [Double] {
        var seen = Set<Int>()
        var sizes: [Double] = []
        for tool in tools where tool.shankDiameter > 0 {
            if seen.insert(shankKey(tool.shankDiameter)).inserted {
                sizes.append(tool.shankDiameter)
            }
        }
        return sizes.sorted()
    }

    // MARK: Matching

    private enum Facet {
        case stock, type, shank, source
    }

    /// All facets must match. `ignoring` skips one, for the faceted counts.
    private func matches(_ tool: Tool, ignoring ignored: Facet? = nil) -> Bool {
        (ignored == .stock || !stockOnly || tool.quantity > 0)
            && (ignored == .type || type == nil || tool.type == type)
            && (ignored == .shank || matchesShank(tool))
            && (ignored == .source || matchesSource(tool))
            && matches(material: tool)
            && matchesQuery(tool)
    }

    private func matchesShank(_ tool: Tool) -> Bool {
        guard let shank else { return true }
        return Self.shankKey(shank) == Self.shankKey(tool.shankDiameter)
    }

    private func matches(material tool: Tool) -> Bool {
        switch material {
            case .any: true
            case .metal: tool.isForMetal
            case .nonMetal: !tool.isForMetal
        }
    }

    private func matchesSource(_ tool: Tool) -> Bool {
        switch source {
            case .any: true
            case .source(let id): tool.sourceID == id
        }
    }

    /// Every word typed must appear somewhere in the tool's name, type or diameter.
    /// Case-insensitive, any order: "ball 3.175" finds "3.175mm Ball Nose".
    private func matchesQuery(_ tool: Tool) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }

        let haystack = Self.searchText(for: tool)
        return words.allSatisfy { haystack.contains($0) }
    }

    private static func searchText(for tool: Tool) -> String {
        [
            tool.name,
            tool.type.displayName,
            String(format: "%g", tool.toolDiameter)
        ]
        .joined(separator: " ")
        .lowercased()
    }

    // MARK: Sorting

    private static let typeOrder: [ToolType: Int] = Dictionary(
        uniqueKeysWithValues: ToolType.allCases.enumerated().map { ($0.element, $0.offset) }
    )

    /// Type (in `ToolType.allCases` order), then diameter, then length, then name.
    /// Inside a single type the first comparison is a tie, so it reads as diameter-first.
    private static func areInOrder(_ a: Tool, _ b: Tool) -> Bool {
        let typeA = typeOrder[a.type] ?? Int.max
        let typeB = typeOrder[b.type] ?? Int.max
        if typeA != typeB { return typeA < typeB }

        if a.toolDiameter != b.toolDiameter { return a.toolDiameter < b.toolDiameter }

        let lengthA = a.length ?? 0
        let lengthB = b.length ?? 0
        if lengthA != lengthB { return lengthA < lengthB }

        switch a.name.localizedStandardCompare(b.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.id.uuidString < b.id.uuidString
        }
    }
}
