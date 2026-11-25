//
//  CNCProject.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import simd

struct ProjectData: Identifiable, Codable, Hashable {

    /// The layout of `project.json` this app writes. A file with a higher number was saved by a
    /// newer app and is left alone instead of being rewritten with fields dropped.
    static let currentSchemaVersion = 1
    /// `nil` in files saved before the version was stamped (version 1 layout).
    var schemaVersion: Int?

    /// The project's id, same as in `projects.json`, so a folder can be
    /// recognised on its own (reinstalled app, lost index, folder renamed).
    /// Projects saved before this was stamped carry an unrelated random id,
    /// which `ProjectModel` overwrites on the next load.
    var id: UUID
    /// The project's display name, for the same reason. `nil` in older files.
    var name: String?
    var stock: StockMaterial?
    var isStockVisible: Bool?
    var assets: [AssetData]?
    /// XY offset set in the Controller (where the job's origin sits on the
    /// bed), in millimeters. Saved as `[x, y]`. `nil` in projects saved before
    /// this existed, which load with a zero offset.
    var xyOffset: SIMD2<Float>?
    /// The faces the stock is machined from, in machining order (see `Setup`): a name, the
    /// angle and axis the stock is turned by, and the id of the stock it is cut from (`stocks`).
    /// Toolpaths point at one by `ToolpathData.setupID`.
    /// `nil` until the project has been saved with them: it then has the top only.
    var setups: [Setup]?
    /// The project's stocks (see `ProjectStock`), shared by the setups, each with the fixtures
    /// (alignment pins) attached to it. `nil` in projects saved before: `ProjectStocks.migrate`
    /// builds the list from their setups' own stocks and `alignmentPins`.
    var stocks: [ProjectStock]?
    /// Only what projects saved before fixtures belonged to stocks have: the alignment pins as
    /// objects. Read once by `ProjectStocks.migrate` and cleared; never written by the app now.
    var alignmentPins: [AlignmentPinsData]?

    init(id: UUID = UUID(),
         name: String? = nil,
         stock: StockMaterial?,
         isStockVisible: Bool?,
         assets: [AssetData]?,
         xyOffset: SIMD2<Float>? = nil,
         setups: [Setup]? = nil,
         stocks: [ProjectStock]? = nil) {

        self.id = id
        self.name = name
        self.stock = stock
        self.isStockVisible = isStockVisible
        self.assets = assets
        self.xyOffset = xyOffset
        self.setups = setups
        self.stocks = stocks
    }
}
