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
    var link: String?
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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case material
        case geometry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        material = try container.decode(StockMaterialType.self, forKey: .material)
        geometry = try container.decode(StockGeometry.self, forKey: .geometry)
    }
}
