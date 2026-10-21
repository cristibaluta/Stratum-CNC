//
//  AssetData.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 01/09/2026.
//

import Foundation

struct AssetTransform: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
}

struct AssetData: Codable, Hashable {
    let name: String
    // Transformations relative to the original position
    var transform: AssetTransform?
    // One archive can produce several canvas objects, each with its own identity.
    var objects: [AssetObjectData]? = nil
}

struct AssetObjectData: Codable, Hashable {
    let id: UUID
    let name: String
    var transform: AssetTransform
}
