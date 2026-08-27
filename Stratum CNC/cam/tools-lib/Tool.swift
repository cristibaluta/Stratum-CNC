//
//  Tool.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct Tool: Identifiable, Codable, Hashable {
    let id: UUID

    var name: String

    // Geometry
    var shankDiameter: Double
    var toolDiameter: Double
    var length: Double?

    var type: ToolType
    var group: String?

    // Optional geometry specific to certain tools
    var tipAngle: Double?

    // Cutting parameters by material
    var parameters: [String: ToolCuttingParameters]

    init(
        id: UUID = UUID(),
        name: String,
        shankDiameter: Double,
        toolDiameter: Double,
        length: Double?,
        type: ToolType,
        group: String? = nil,
        tipAngle: Double? = nil,
        parameters: [String: ToolCuttingParameters] = [:]
    ) {
        self.id = id
        self.name = name
        self.shankDiameter = shankDiameter
        self.toolDiameter = toolDiameter
        self.length = length
        self.type = type
        self.group = group
        self.tipAngle = tipAngle
        self.parameters = parameters
    }

    var displayName: String {
        let lengthString = String(format: "%.3g", length ?? -1)

        return "\(shankDiameter)×\(toolDiameter)×\(lengthString) - \(type.displayName)"
    }
}

enum ToolType: String, Codable, CaseIterable, Hashable {
    case endMill
    case ballNose
    case engraving
    case drill
    case vBit
    case corn
    case chamfer
    case solderMaskRemover

    var displayName: String {
        switch self {
        case .endMill:
            "End Mill"
        case .ballNose:
            "Ball Nose"
        case .engraving:
            "Engraving"
        case .drill:
            "Drill"
        case .vBit:
            "V Bit"
        case .corn:
            "Corn"
        case .chamfer:
            "Chamfer"
        case .solderMaskRemover:
            "Solder Mask Remover"
        }
    }
}

enum ToolMaterial: String, Codable, CaseIterable, Hashable {
    case aluminum
    case brass
    case carbonFiber
    case copper
    case hardwood
    case pcb
    case plastic
    case softwood

    var displayName: String {
        switch self {
        case .aluminum:
            "Aluminum"
        case .brass:
            "Brass"
        case .carbonFiber:
            "Carbon Fiber"
        case .copper:
            "Copper"
        case .hardwood:
            "Hardwood"
        case .pcb:
            "PCB"
        case .plastic:
            "Plastic"
        case .softwood:
            "Softwood"
        }
    }
}

struct ToolCuttingParameters: Codable, Hashable {
    var spindleRPM: Int?
    var feedRate: Double?
    var plungeFeedRate: Double?
    var depthOfCut: Double?

//    init(
//        spindleRPM: Int = 0,
//        feedRate: Double = 0,
//        plungeFeedRate: Double = 0,
//        depthOfCut: Double = 0
//    ) {
//        self.spindleRPM = spindleRPM
//        self.feedRate = feedRate
//        self.plungeFeedRate = plungeFeedRate
//        self.depthOfCut = depthOfCut
//    }
}
