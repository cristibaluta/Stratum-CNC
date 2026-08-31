//
//  CNCProject.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct ProjectAsset: Codable, Hashable {
    let name: String
}

struct ProjectData: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var modifiedAt: Date
    var material: StockMaterial?
    var assets: [ProjectAsset]?

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = .now,
         modifiedAt: Date = .now,
         material: StockMaterial?,
         assets: [ProjectAsset]?) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.material = material
        self.assets = assets
    }
}
