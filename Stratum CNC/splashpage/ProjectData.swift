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
    /// Only what projects saved before stocks were a list have: a root stock. Read once to seed the
    /// stocks list (`ProjectStocks.migrate`); never written.
    var legacyStock: StockMaterial?
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
    /// The groups (virtual objects, see `ObjectGroup`). `nil` in projects saved before they existed.
    var objectGroups: [ObjectGroup]?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, assets, xyOffset, setups, stocks, alignmentPins, objectGroups
        // Read only, from files saved before: `stock` is now in `stocks`; `isStockVisible` is UI state
        case stock, isStockVisible
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        legacyStock = try c.decodeIfPresent(StockMaterial.self, forKey: .stock)
        assets = try c.decodeIfPresent([AssetData].self, forKey: .assets)
        xyOffset = try c.decodeIfPresent(SIMD2<Float>.self, forKey: .xyOffset)
        setups = try c.decodeIfPresent([Setup].self, forKey: .setups)
        stocks = try c.decodeIfPresent([ProjectStock].self, forKey: .stocks)
        alignmentPins = try c.decodeIfPresent([AlignmentPinsData].self, forKey: .alignmentPins)
        objectGroups = try c.decodeIfPresent([ObjectGroup].self, forKey: .objectGroups)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(assets, forKey: .assets)
        try c.encodeIfPresent(xyOffset, forKey: .xyOffset)
        try c.encodeIfPresent(setups, forKey: .setups)
        try c.encodeIfPresent(stocks, forKey: .stocks)
        try c.encodeIfPresent(alignmentPins, forKey: .alignmentPins)
        try c.encodeIfPresent(objectGroups, forKey: .objectGroups)
    }

    init(id: UUID = UUID(),
         name: String? = nil,
         assets: [AssetData]?,
         xyOffset: SIMD2<Float>? = nil,
         setups: [Setup]? = nil,
         stocks: [ProjectStock]? = nil) {

        self.id = id
        self.name = name
        self.assets = assets
        self.xyOffset = xyOffset
        self.setups = setups
        self.stocks = stocks
    }
}
