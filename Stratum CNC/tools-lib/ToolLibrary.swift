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

    /// Version written by this build. 2 added `sources` and `Tool.sourceID`.
    static let currentSchemaVersion = 2

    enum CodingKeys: String, CodingKey {
        case schemaVersion, source, tools, sources, laserSettings, threadMilling
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        source = try c.decode(ToolLibrarySource.self, forKey: .source)
        tools = try c.decode([Tool].self, forKey: .tools)
        laserSettings = try c.decodeIfPresent(LaserSettings.self, forKey: .laserSettings)
        threadMilling = try c.decodeIfPresent(ThreadMillingSettings.self, forKey: .threadMilling)

        // A file from before sources existed has no `sources`. The bundled and custom sources
        // always exist, so add them if they are missing; imports keep their order after them.
        var decoded = try c.decodeIfPresent([ToolSourceInfo].self, forKey: .sources) ?? []
        if !decoded.contains(where: { $0.id == ToolSourceInfo.customID }) {
            decoded.insert(.custom, at: 0)
        }
        if !decoded.contains(where: { $0.id == ToolSourceInfo.bundledID }) {
            decoded.insert(.bundled, at: 0)
        }
        sources = decoded
    }
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
