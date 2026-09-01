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
        case .aluminum:
            "Aluminum"
        case .steel:
            "Steel"
        case .stainless_steel:
            "Stainless Steel"
        case .brass:
            "Brass"
        case .bronze:
            "Bronze"
        case .copper:
            "Copper"
        case .wood:
            "Wood"
        case .hardwood:
            "Hardwood"
        case .softwood:
            "Softwood"
        case .plywood:
            "Plywood"
        case .plastic:
            "Plastic"
        case .acrylic:
            "Acrylic"
        case .hdpe:
            "HDPE"
        case .pvc:
            "PVC"
        case .delrin:
            "Delrin / POM"
        case .carbon_fiber:
            "Carbon Fiber"
        case .pcb:
            "PCB"
        case .custom:
            "Custom"
        case .epoxy:
            "Epoxy"
        case .bakelite:
            "Bakelite"
        case .synthetic_stone:
            "Synthetic Stone"
        case .polycarbonate:
            "Polycarbonate"
        case .bicolor_stock:
            "Bicolor Stock"
        }
    }
}
