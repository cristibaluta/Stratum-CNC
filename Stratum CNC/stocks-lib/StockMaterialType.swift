//
//  StockMaterialType.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

enum StockMaterialType: String, Codable, CaseIterable, Hashable {
    case aluminum
    case steel
    case stainless_steel
    case brass
    case bronze
    case copper

    case wood
    case hardwood
    case softwood
    case plywood

    case plastic
    case acrylic
    case hdpe
    case pvc
    case delrin

    case carbon_fiber
    case pcb

    case epoxy
    case bakelite
    case synthetic_stone
    case polycarbonate
    case bicolor_stock

    case custom

    var displayName: String {
        switch self {
            case .stainless_steel: "Stainless Steel"
            case .hdpe: "HDPE"
            case .pvc: "PVC"
            case .delrin: "Delrin / POM"
            case .carbon_fiber: "Carbon Fiber"
            case .synthetic_stone: "Synthetic Stone"
            case .bicolor_stock: "Bicolor Stock"
            default: self.rawValue.capitalized
        }
    }

    /// Whether the stock is a metal, for offering the tools meant for cutting metal.
    var isMetal: Bool {
        switch self {
        case .aluminum, .steel, .stainless_steel, .brass, .bronze, .copper:
            true
        default:
            false
        }
    }

    /// Preset names that suit this stock, best match first. Compared ignoring case,
    /// spaces, hyphens and underscores, so "Carbon Fiber" matches `carbon_fiber`.
    var presetNameCandidates: [String] {
        switch self {
            case .aluminum:         ["aluminum", "aluminium"]
            case .steel:            ["steel"]
            case .stainless_steel:  ["stainlesssteel", "steel"]
            case .brass:            ["brass"]
            case .bronze:           ["bronze", "brass", "copper"]
            case .copper:           ["copper"]
            case .wood:             ["wood", "hardwood", "softwood"]
            case .hardwood:         ["hardwood", "wood"]
            case .softwood:         ["softwood", "wood"]
            case .plywood:          ["plywood", "softwood", "wood"]
            case .plastic:          ["plastic"]
            case .acrylic:          ["acrylic", "plastic"]
            case .hdpe:             ["hdpe", "plastic"]
            case .pvc:              ["pvc", "plastic"]
            case .delrin:           ["delrin", "pom", "plastic"]
            case .polycarbonate:    ["polycarbonate", "plastic"]
            case .epoxy:            ["epoxy", "plastic"]
            case .bakelite:         ["bakelite", "plastic"]
            case .carbon_fiber:     ["carbonfiber"]
            case .pcb:              ["pcb"]
            case .synthetic_stone:  ["syntheticstone"]
            case .bicolor_stock:    ["bicolorstock"]
            case .custom:           []
        }
    }
}
