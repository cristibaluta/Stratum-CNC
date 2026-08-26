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
    case stainlessSteel
    case brass
    case bronze
    case copper

    case wood
    case hardwood
    case softwood
    case plywood
    case mdf

    case plastic
    case acrylic
    case hdpe
    case pvc
    case delrin

    case carbonFiber
    case pcb

    case custom

    var displayName: String {
        switch self {
        case .aluminum:
            "Aluminum"
        case .steel:
            "Steel"
        case .stainlessSteel:
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
        case .mdf:
            "MDF"
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
        case .carbonFiber:
            "Carbon Fiber"
        case .pcb:
            "PCB"
        case .custom:
            "Custom"
        }
    }
}
