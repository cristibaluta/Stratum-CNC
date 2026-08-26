//
//  ThreadMillingPreset.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct ThreadMillingPreset: Identifiable, Codable, Hashable {
    let id: UUID

    var nominalSize: String
    var threadPitch: Double
    var tappingDrillSize: Double

    var woodsAndPlastics: ToolCuttingParameters
    var metals: ToolCuttingParameters
    var composites: ToolCuttingParameters

    init(
        id: UUID = UUID(),
        nominalSize: String,
        threadPitch: Double,
        tappingDrillSize: Double,
        woodsAndPlastics: ToolCuttingParameters,
        metals: ToolCuttingParameters,
        composites: ToolCuttingParameters
    ) {
        self.id = id
        self.nominalSize = nominalSize
        self.threadPitch = threadPitch
        self.tappingDrillSize = tappingDrillSize
        self.woodsAndPlastics = woodsAndPlastics
        self.metals = metals
        self.composites = composites
    }
}
