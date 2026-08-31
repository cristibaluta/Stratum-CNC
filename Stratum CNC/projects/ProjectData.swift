//
//  CNCProject.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct AssetData: Codable, Hashable {
    let name: String
}

struct ProjectData: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var modifiedAt: Date
    var stock: StockMaterial?
    var isStockVisible: Bool?
    var assets: [AssetData]?

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = .now,
         modifiedAt: Date = .now,
         stock: StockMaterial?,
         isStockVisible: Bool?,
         assets: [AssetData]?) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.stock = stock
        self.isStockVisible = isStockVisible
        self.assets = assets
    }
}
