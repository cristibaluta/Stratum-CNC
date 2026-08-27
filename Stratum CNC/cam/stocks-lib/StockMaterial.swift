//
//  StockMaterial 2.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct StockMaterial: Identifiable, Codable, Hashable {
    let id: UUID

    var name: String
    var material: StockMaterialType
    var geometry: StockGeometry

    init(
        id: UUID = UUID(),
        name: String,
        material: StockMaterialType,
        geometry: StockGeometry
    ) {
        self.id = id
        self.name = name
        self.material = material
        self.geometry = geometry
    }
}
