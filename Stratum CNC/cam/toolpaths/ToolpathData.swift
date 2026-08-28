//
//  ContourToolpath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolpathData: Identifiable {
    let id = UUID()

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
}

enum ContourType: String, CaseIterable {
    case inside = "Inside"
    case outside = "Outside"
    case outline = "Outline"
}
