//
//  StockGeometry.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

enum StockGeometry: Codable, Hashable, CaseIterable {
    case rectangular(width: Double, height: Double, depth: Double)
    case cylindrical(diameter: Double, length: Double)
    case disk(outerDiameter: Double, innerDiameter: Double, depth: Double)

    var displayName: String {
        switch self {
            case .rectangular: "Rectangular"
            case .cylindrical: "Cylindrical"
            case .disk: "Disk"
        }
    }

    var dimensionsDescription: String {
        switch self {
            case let .rectangular(width, height, depth):           "\(width) × \(height) × \(depth) mm"
            case let .cylindrical(diameter, length):               "Ø\(diameter) × \(length) mm"
            case let .disk(outerDiameter, innerDiameter, depth):   "Ø\(outerDiameter) / Ø\(innerDiameter) × \(depth) mm"
        }
    }

    static var allCases: [StockGeometry] {
        return [
            .rectangular(width: 100, height: 50, depth: 10),
            .cylindrical(diameter: 20, length: 200),
            .disk(outerDiameter: 50, innerDiameter: 15, depth: 13)
        ]
    }
}
