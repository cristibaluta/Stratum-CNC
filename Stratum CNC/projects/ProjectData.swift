//
//  CNCProject.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import simd

struct ProjectData: Identifiable, Codable, Hashable {

    let id: UUID
    var stock: StockMaterial?
    var isStockVisible: Bool?
    var assets: [AssetData]?
    /// XY offset set in the Controller (where the job's origin sits on the
    /// bed), in millimeters. Saved as `[x, y]`. `nil` in projects saved before
    /// this existed, which load with a zero offset.
    var xyOffset: SIMD2<Float>?

    init(id: UUID = UUID(),
         stock: StockMaterial?,
         isStockVisible: Bool?,
         assets: [AssetData]?,
         xyOffset: SIMD2<Float>? = nil) {
        
        self.id = id
        self.stock = stock
        self.isStockVisible = isStockVisible
        self.assets = assets
        self.xyOffset = xyOffset
    }
}
