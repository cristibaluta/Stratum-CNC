//
//  CNCProject.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import simd

struct ProjectData: Identifiable, Codable, Hashable {

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

    init(id: UUID = UUID(),
         name: String? = nil,
         stock: StockMaterial?,
         isStockVisible: Bool?,
         assets: [AssetData]?,
         xyOffset: SIMD2<Float>? = nil) {
        
        self.id = id
        self.name = name
        self.stock = stock
        self.isStockVisible = isStockVisible
        self.assets = assets
        self.xyOffset = xyOffset
    }
}
