//
//  LaserMaterialPreset.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct LaserMaterialPreset: Identifiable, Codable, Hashable {
    let id: UUID

    var material: String
    var suggestedThicknessCut: String?

    var vectorEngrave: LaserOperation?
    var vectorCut: LaserOperation?
    var imageEngrave: LaserOperation?

    init(
        id: UUID = UUID(),
        material: String,
        suggestedThicknessCut: String? = nil,
        vectorEngrave: LaserOperation? = nil,
        vectorCut: LaserOperation? = nil,
        imageEngrave: LaserOperation? = nil
    ) {
        self.id = id
        self.material = material
        self.suggestedThicknessCut = suggestedThicknessCut
        self.vectorEngrave = vectorEngrave
        self.vectorCut = vectorCut
        self.imageEngrave = imageEngrave
    }
}

struct LaserOperation: Codable, Hashable {
    var speed: Double
    var power: Double
    var passes: String
}
