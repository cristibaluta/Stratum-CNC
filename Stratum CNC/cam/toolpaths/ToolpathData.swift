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

    /// The contours (paths on the canvas) this toolpath cuts. Empty until the
    /// user picks some — picked on the canvas while the toolpath is open (see CAMModel.selectedToolpathID).
    var targets: [PathSelection] = []

    /// What the toolpath does (contour, pocket, drill…) and that operation's own options.
    /// `contour` (the contour's side) and `ramping` (the entry) above are used by the
    /// operations that have them; see `OperationKind`.
    var operation = OperationSettings()

    // Explicit so the legacy single-contour `target` key can be read on decode
    // (see init(from:) below) without being written back on encode.
    private enum CodingKeys: String, CodingKey {
        case id, name, tool
        case startZ, endZ
        case contour, ramping
        case feedRate, plungeRate, spindleRPM
        case stepDown, stepOver, safeZ
        case targets
        case operation
    }
}

// Kept in an extension so the compiler-generated memberwise init survives.
extension ToolpathData {

    /// Projects saved before multi-shape support stored one optional `target`.
    private enum LegacyKeys: String, CodingKey {
        case target
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tool = try c.decode(Tool.self, forKey: .tool)
        startZ = try c.decode(Double.self, forKey: .startZ)
        endZ = try c.decode(Double.self, forKey: .endZ)
        contour = try c.decode(ContourType.self, forKey: .contour)
        ramping = try c.decode(RampingSettings.self, forKey: .ramping)
        feedRate = try c.decode(Double.self, forKey: .feedRate)
        plungeRate = try c.decode(Double.self, forKey: .plungeRate)
        spindleRPM = try c.decode(Int.self, forKey: .spindleRPM)
        stepDown = try c.decode(Double.self, forKey: .stepDown)
        stepOver = try c.decode(Double.self, forKey: .stepOver)
        safeZ = try c.decode(Double.self, forKey: .safeZ)

        targets = try c.decodeIfPresent([PathSelection].self, forKey: .targets) ?? []

        // Projects saved before operations existed were all contours.
        operation = try c.decodeIfPresent(OperationSettings.self, forKey: .operation) ?? OperationSettings()

        if targets.isEmpty {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let old = try legacy.decodeIfPresent(PathSelection.self, forKey: .target) {
                targets = [old]
            }
        }
    }
}

enum ContourType: String, CaseIterable, Codable, Hashable {
    case inside = "Inside"
    case outside = "Outside"
    case outline = "Outline"
}
