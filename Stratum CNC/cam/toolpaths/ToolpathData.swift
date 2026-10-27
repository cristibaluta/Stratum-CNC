//
//  ContourToolpath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI
import StratumCAM

struct ToolpathData: Identifiable, Codable, Hashable {
    var id = UUID()

    var name: String

    /// True once the user has typed their own name for this toolpath. Until then,
    /// `name` follows the chosen operation automatically (see `PanelToolpathDetails`)
    /// and gets renamed whenever the operation changes.
    var isNameCustom: Bool = false

    var tool: Tool

    var startZ: Double
    var endZ: Double

    var contour: SC.CutSide
    var ramping: RampingSettings

    var feedRate: Double
    var plungeRate: Double
    var spindleRPM: Int

    var stepDown: Double
    /// Width per pass as a percentage of the tool diameter (see `stepOverRange`). Always stored
    /// and edited as a percentage, so changing the tool keeps it; the mm value is derived
    /// (`stepOverMM`).
    var stepOverPercent: Double
    var safeZ: Double

    /// The contours (paths on the canvas) this toolpath cuts. Empty until the
    /// user picks some — picked on the canvas while the toolpath is open (see CAMModel.selectedToolpathID).
    var targets: [PathSelection] = []

    /// What the toolpath does (contour, pocket, drill…) and that operation's own options.
    /// `contour` (the contour's side) and `ramping` (the entry) above are used by the
    /// operations that have them; see `OperationKind`.
    var operation = OperationSettings()

    /// General fields the user has set by hand (or a tool preset has). Those keep their value
    /// when the operation changes; the others follow the operation's defaults
    /// (see `OperationDefaults`).
    var editedFields: Set<ToolpathField> = []

    // Explicit so the legacy single-contour `target` key can be read on decode
    // (see init(from:) below) without being written back on encode.
    private enum CodingKeys: String, CodingKey {
        case id, name, isNameCustom, tool
        case startZ, endZ
        case contour, ramping
        case feedRate, plungeRate, spindleRPM
        case stepDown, stepOverPercent, safeZ
        case targets
        case operation, editedFields
    }
}

extension ToolpathData {

    /// The only place the stepover limits live (% of tool diameter), matching what the
    /// generator accepts.
    static let stepOverRange: ClosedRange<Double> = 10...95

    static func clampedStepOver(_ percent: Double) -> Double {
        min(max(percent, stepOverRange.lowerBound), stepOverRange.upperBound)
    }

    /// The stepover as a fraction of the tool diameter, which is what the library takes.
    var stepOverFraction: Double {
        stepOverPercent / 100
    }

    /// Read-out only: the distance between passes in mm for the current tool.
    var stepOverMM: Double {
        Double(tool.toolDiameter) * stepOverFraction
    }

    /// Keys of older projects, which stored the stepover in mm.
    private enum LegacyCodingKeys: String, CodingKey {
        case stepOver
    }
}

// Kept in an extension so the compiler-generated memberwise init survives.
extension ToolpathData {

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // Absent on projects saved before renaming existed -- treat as auto-generated.
        isNameCustom = try c.decodeIfPresent(Bool.self, forKey: .isNameCustom) ?? false
        tool = try c.decode(Tool.self, forKey: .tool)
        startZ = try c.decode(Double.self, forKey: .startZ)
        endZ = try c.decode(Double.self, forKey: .endZ)
        contour = try c.decode(SC.CutSide.self, forKey: .contour)
        ramping = try c.decode(RampingSettings.self, forKey: .ramping)
        feedRate = try c.decode(Double.self, forKey: .feedRate)
        plungeRate = try c.decode(Double.self, forKey: .plungeRate)
        spindleRPM = try c.decode(Int.self, forKey: .spindleRPM)
        stepDown = try c.decode(Double.self, forKey: .stepDown)
        safeZ = try c.decode(Double.self, forKey: .safeZ)

        // Projects saved before stepover became a percentage stored it in mm: convert it with
        // the saved tool's diameter.
        if let percent = try c.decodeIfPresent(Double.self, forKey: .stepOverPercent) {
            stepOverPercent = Self.clampedStepOver(percent)
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let mm = try legacy.decode(Double.self, forKey: .stepOver)
            let diameter = Double(tool.toolDiameter)
            stepOverPercent = Self.clampedStepOver(diameter > 0 ? mm / diameter * 100 : 40)
        }

        targets = try c.decodeIfPresent([PathSelection].self, forKey: .targets) ?? []

        // Projects saved before operations existed were all contours.
        operation = try c.decodeIfPresent(OperationSettings.self, forKey: .operation) ?? OperationSettings()

        // Absent on projects saved before defaults existed: nothing counts as edited, so those
        // projects' values are only replaced if the operation is changed.
        editedFields = try c.decodeIfPresent(Set<ToolpathField>.self, forKey: .editedFields) ?? []
    }
}
