//
//  StockMaterial 2.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import SwiftDXF
import StratumCAM

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

    /// The stock seen from above (X by Y, mm). Round stock is covered by its bounding square.
    var footprintSize: (width: Double, height: Double) {
        switch geometry {
            case .rectangular(let width, let height, _):
                return (width, height)
            case .cylindrical(let diameter, _):
                return (diameter, diameter)
            case .disk(let outerDiameter, _, _):
                return (outerDiameter, outerDiameter)
        }
    }

    /// A closed rectangle around the stock's footprint, from the origin (0, 0) -- the bottom-left
    /// corner of the stock in machine coordinates -- to (width, height). What a facing toolpath
    /// set to "Whole stock" cuts instead of the selected shapes.
    var footprintContour: SC.Contour {
        let size = footprintSize
        let corners = [(0.0, 0.0), (size.width, 0.0), (size.width, size.height), (0.0, size.height)]
        let chain = corners.indices.compactMap { index -> SC.Contour.Chained? in
            let start = corners[index]
            let end = corners[(index + 1) % corners.count]
            let line = SwiftDXF.DXF.Entity.line(a: SwiftDXF.DXF.Point(start.0, start.1),
                                                b: SwiftDXF.DXF.Point(end.0, end.1),
                                                layer: "0",
                                                color: 0)
            return SC.Geometry(dxf: line).map { SC.Contour.Chained(geometry: $0, reversed: false) }
        }
        return SC.Contour(entities: chain, isClosed: true)
    }
}

extension StockMaterial {

    /// The material and the size on one line, for a project card: "Aluminum · 100 × 100 × 10 mm".
    var cardSummary: String {
        func format(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        }
        let size: String
        switch geometry {
            case .rectangular(let width, let height, let depth):
                size = "\(format(width)) × \(format(height)) × \(format(depth)) mm"
            case .cylindrical(let diameter, let length):
                size = "Ø\(format(diameter)) × \(format(length)) mm"
            case .disk(let outerDiameter, let innerDiameter, let depth):
                size = "Ø\(format(outerDiameter)) / Ø\(format(innerDiameter)) × \(format(depth)) mm"
        }
        return "\(material.displayName) · \(size)"
    }
}
