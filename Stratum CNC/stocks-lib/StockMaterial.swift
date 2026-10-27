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
    var quantity: Int
    var material: StockMaterialType
    var geometry: StockGeometry

    init(
        id: UUID = UUID(),
        name: String,
        link: String? = nil,
        quantity: Int = 0,
        material: StockMaterialType,
        geometry: StockGeometry
    ) {
        self.id = id
        self.name = name
        self.link = link
        self.quantity = quantity
        self.material = material
        self.geometry = geometry
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case link
        case quantity
        case material
        case geometry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 0
        material = try container.decode(StockMaterialType.self, forKey: .material)
        geometry = try container.decode(StockGeometry.self, forKey: .geometry)
    }

    /// The link as a URL, if it is a valid http(s) address.
    var linkURL: URL? {
        guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty,
              let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}

extension StockMaterial {

    /// The stock's size along Z (mm): the depth of a rectangular block or a disk, the
    /// length of a cylinder (laid flat, like the stock panel draws it). Used by the
    /// "Through stock" helper to set End Z.
    var thickness: Double {
        switch geometry {
            case .rectangular(_, _, let depth):
                return depth
            case .cylindrical(_, let length):
                return length
            case .disk(_, _, let depth):
                return depth
        }
    }
}
