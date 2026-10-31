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

/// Which tools the rail has selected.
enum ToolScope: Hashable {
    case all
    case inStock
    case type(ToolType)
}

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

    var scope: ToolScope = .all
    var material: MaterialFilter = .any
    var source: ToolSourceFilter = .any
    var query: String = ""

    // MARK: Refinements

    /// True when something other than the rail selection narrows the list.
    /// Drives the "Clear filters" button in the empty state.
    var hasRefinements: Bool {
        material != .any
            || source != .any
            || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Resets search, material and source. The rail selection is left alone.
    mutating func clearRefinements() {
        material = .any
        source = .any
        query = ""
    }

    // MARK: Apply

    /// The tools to show: filtered by scope and every refinement, then sorted.
    func apply(to tools: [Tool]) -> [Tool] {
        tools
            .filter { matchesRefinements($0) && Self.matches(scope: scope, tool: $0) }
            .sorted(by: Self.areInOrder)
    }

    /// Counts for the Source dropdown, keyed by source id. Faceted like the rail: they respect
    /// the scope, material and search, but not the source filter itself, so each entry is how
    /// many tools the list would show if that source were picked. Missing entry means zero.
    func sourceCounts(in tools: [Tool]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for tool in tools
        where Self.matches(scope: scope, tool: tool) && matches(material: tool) && matchesQuery(tool) {
            result[tool.sourceID, default: 0] += 1
        }
        return result
    }

    /// Rail counts. Faceted: they respect search, material and source, but not the scope
    /// itself, so every row shows how many tools it would list right now.
    /// Types that don't appear in the result have no entry; read with `counts[.type(t), default: 0]`.
    func counts(in tools: [Tool]) -> [ToolScope: Int] {
        var result: [ToolScope: Int] = [.all: 0, .inStock: 0]
        for tool in tools where matchesRefinements(tool) {
            result[.all, default: 0] += 1
            if tool.quantity > 0 {
                result[.inStock, default: 0] += 1
            }
            result[.type(tool.type), default: 0] += 1
        }
        return result
    }

    // MARK: Matching

    private func matchesRefinements(_ tool: Tool) -> Bool {
        matches(material: tool) && matchesSource(tool) && matchesQuery(tool)
    }

    private static func matches(scope: ToolScope, tool: Tool) -> Bool {
        switch scope {
            case .all: true
            case .inStock: tool.quantity > 0
            case .type(let type): tool.type == type
        }
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
