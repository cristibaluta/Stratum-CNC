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

    /// The shape type without its dimensions. Use this (not the full value) for pickers.
    enum Kind: String, CaseIterable, Identifiable {
        case rectangular
        case cylindrical
        case disk

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .rectangular: "Rectangular"
            case .cylindrical: "Cylindrical"
            case .disk: "Disk"
            }
        }
    }

    /// Primary sort value: footprint area (width × height).
    /// Cylinders use their side profile (diameter × length), disks their outer diameter squared.
    var sortArea: Double {
        switch self {
        case let .rectangular(width, height, _): width * height
        case let .cylindrical(diameter, length): diameter * length
        case let .disk(outerDiameter, _, _): outerDiameter * outerDiameter
        }
    }

    /// Secondary sort value (lower weight): depth, or diameter for cylinders.
    var sortDepth: Double {
        switch self {
        case let .rectangular(_, _, depth): depth
        case let .cylindrical(diameter, _): diameter
        case let .disk(_, _, depth): depth
        }
    }

    var kind: Kind {
        switch self {
        case .rectangular: .rectangular
        case .cylindrical: .cylindrical
        case .disk: .disk
        }
    }

    /// Returns this geometry converted to another shape type, carrying over
    /// the dimensions that make sense. Returns self if the kind is unchanged.
    func converted(to newKind: Kind) -> StockGeometry {
        guard newKind != kind else {
            return self
        }

        // Reduce the current shape to a footprint size and a thickness/length.
        let size: Double
        let extent: Double
        switch self {
        case let .rectangular(width, height, depth):
            size = min(width, height)
            extent = newKind == .cylindrical ? max(width, height) : depth
        case let .cylindrical(diameter, length):
            size = diameter
            extent = length
        case let .disk(outerDiameter, _, depth):
            size = outerDiameter
            extent = depth
        }

        switch newKind {
        case .rectangular:
            return .rectangular(width: size, height: size, depth: extent)
        case .cylindrical:
            return .cylindrical(diameter: size, length: extent)
        case .disk:
            return .disk(outerDiameter: size, innerDiameter: (size * 0.3).rounded(), depth: extent)
        }
    }

    var id: String {
        switch self {
        case .rectangular: return "rectangular"
        case .cylindrical: return "cylindrical"
        case .disk: return "disk"
        }
    }

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
