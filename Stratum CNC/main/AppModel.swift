//
//  MainModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.08.2026.
//

import SwiftUI

@MainActor
class AppModel: ObservableObject {

    @Published var projectsStore = ProjectsStore()
    @Published var toolsStore = ToolsStore()
    @Published var stocksStore = StocksStore()

    @Published var showingNewProject = false
    @Published var showingToolsSheet: Bool = false
    @Published var showingStocksSheet: Bool = false

    private var toolsSheetContinuation: CheckedContinuation<Tool?, Never>?
    private var stocksSheetContinuation: CheckedContinuation<StockMaterial?, Never>?

    /// True while someone is waiting for a tool to be picked. The tools sheet
    /// uses this to decide whether to show its "Pick" button (picker mode)
    /// or to behave as a plain library browser/editor.
    var isPickingTool: Bool { toolsSheetContinuation != nil }

    // MARK: - Recent tools

    private static let recentToolIDsKey = "app.recentToolIDs"
    private static let recentToolsLimit = 5

    /// Ids of the last tools used, most recent first. Persisted in UserDefaults.
    @Published private(set) var recentToolIDs: [UUID] = {
        let strings = UserDefaults.standard.stringArray(forKey: AppModel.recentToolIDsKey) ?? []
        return strings.compactMap(UUID.init(uuidString:))
    }()

    /// The recent tools resolved against the library, most recent first.
    /// Ids of tools that were deleted from the library are skipped.
    var recentTools: [Tool] {
        recentToolIDs.compactMap { id in toolsStore.tools.first { $0.id == id } }
    }

    /// Call whenever a tool gets assigned to a toolpath.
    func noteToolUsed(_ tool: Tool) {
        var ids = recentToolIDs.filter { $0 != tool.id }
        ids.insert(tool.id, at: 0)
        recentToolIDs = Array(ids.prefix(Self.recentToolsLimit))
        UserDefaults.standard.set(recentToolIDs.map(\.uuidString), forKey: Self.recentToolIDsKey)
    }

    // MARK: - App-wide appearance

    /// App-wide day/night switch. Drives `.preferredColorScheme` for the
    /// whole app from the root (`ContentView`), so every screen — Projects,
    /// CAM, Controller — follows the same explicit choice instead of each
    /// screen deciding its own appearance. Persisted, like the other
    /// standing preferences in this app.
    @Published var isDarkMode: Bool = UserDefaults.standard.bool(forKey: "app.isDarkMode") {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: "app.isDarkMode")
        }
    }

    // MARK: - Pickers

    func pickStockMaterial() async -> StockMaterial? {
        await withCheckedContinuation { continuation in
            stocksSheetContinuation = continuation
            showingStocksSheet = true
        }
    }

    func resolveStockPick(_ material: StockMaterial?) {
        stocksSheetContinuation?.resume(returning: material)
        stocksSheetContinuation = nil
        showingStocksSheet = false
    }

    /// Opens the tools library in picker mode and returns the chosen tool,
    /// or `nil` if the sheet was dismissed without picking.
    func pickTool() async -> Tool? {
        await withCheckedContinuation { continuation in
            toolsSheetContinuation = continuation
            showingToolsSheet = true
        }
    }

    func resolveToolPick(_ tool: Tool?) {
        toolsSheetContinuation?.resume(returning: tool)
        toolsSheetContinuation = nil
        showingToolsSheet = false
    }
}
