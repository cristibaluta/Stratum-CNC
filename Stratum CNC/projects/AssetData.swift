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
}
