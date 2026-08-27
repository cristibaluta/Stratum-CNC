//
//  StockGeometry.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

enum StockGeometry: Codable, Hashable {
    case rectangular(width: Double, height: Double, depth: Double)
    case round(diameter: Double, depth: Double)
    case disk(outerDiameter: Double, innerDiameter: Double, depth: Double)
}

extension StockGeometry {

    var displayName: String {
        switch self {
            case .rectangular: "Rectangular"
            case .round: "Round"
            case .disk: "Disk"
        }
    }
}

extension StockGeometry {

    var dimensionsDescription: String {
        switch self {
            case let .rectangular(width, height, depth):           "\(width) × \(height) × \(depth) mm"
            case let .round(diameter, depth):                      "Ø\(diameter) × \(depth) mm"
            case let .disk(outerDiameter, innerDiameter, depth):   "Ø\(outerDiameter) / Ø\(innerDiameter) × \(depth) mm"
        }
    }
}

extension StockGeometry {

    var shape: StockShape {
        switch self {
            case .rectangular: .rectangular
            case .round: .round
            case .disk: .disk
        }
    }
}
