//
//  ToolLibrary.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct ToolLibrary: Codable {

    var schemaVersion: Int
    /// Where the bundled defaults came from (the Makera wiki). Not the per-tool sources below.
    var source: ToolLibrarySource

    var tools: [Tool]

    /// Bundled, custom, then one entry per import.
    var sources: [ToolSourceInfo]

    var laserSettings: LaserSettings?
    var threadMilling: ThreadMillingSettings?
}

struct ToolLibrarySource: Codable {
    var name: String
    var url: String
    var retrieved: String
    var units: ToolLibraryUnits
}

struct ToolLibraryUnits: Codable {
    var diameter: String
    var length: String
    var feedRate: String
    var plungeFeedRate: String
    var depthOfCut: String
    var spindleRPM: String
}

struct LaserSettings: Codable {
    var machine: [String]
    var materials: [String: LaserMaterialPreset]
}

struct ThreadMillingSettings: Codable {
    var shankDiameter: Double
    var tools: [ThreadMillingPreset]
}
