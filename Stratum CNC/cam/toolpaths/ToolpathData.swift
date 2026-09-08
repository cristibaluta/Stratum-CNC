//
//  ContourToolpath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolpathData: Identifiable, Codable, Hashable {
    var id = UUID()

    var name: String

    var tool: Tool

    var startZ: Double
    var endZ: Double

    var contour: ContourType
    var ramping: RampingSettings

    var feedRate: Double
    var plungeRate: Double
    var spindleRPM: Int

    var stepDown: Double
    var stepOver: Double
    var safeZ: Double

    /// Which contour this toolpath cuts. Nil until it's assigned — e.g. by
    /// creating the toolpath from the currently-selected contour.
    var target: PathSelection? = nil
}

enum ContourType: String, CaseIterable, Codable, Hashable {
    case inside = "Inside"
    case outside = "Outside"
    case outline = "Outline"
}
