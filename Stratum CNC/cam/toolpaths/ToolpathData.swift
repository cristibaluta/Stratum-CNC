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

    /// Trochoidal loop pitch, % of the tool radius: what the library accepts (see
    /// `ToolpathGenerator.parameterMessage`).
    static let trochoidalPitchRange: ClosedRange<Double> = 5...100

    static func clampedTrochoidalPitch(_ percent: Double) -> Double {
        min(max(percent, trochoidalPitchRange.lowerBound), trochoidalPitchRange.upperBound)
    }

    /// Adaptive optimal load, % of the tool diameter: the library wants more than 0 and at
    /// most 95 %.
    static let adaptiveLoadRange: ClosedRange<Double> = 1...95

    static func clampedAdaptiveLoad(_ percent: Double) -> Double {
        min(max(percent, adaptiveLoadRange.lowerBound), adaptiveLoadRange.upperBound)
    }

    /// Counterbore depth (mm): what the library accepts.
    static let counterboreDepthRange: ClosedRange<Double> = 0.1...50

    static func clampedCounterboreDepth(_ depth: Double) -> Double {
        min(max(depth, counterboreDepthRange.lowerBound), counterboreDepthRange.upperBound)
    }

    /// A slot's depth per pass and a drill's peck depth (mm): what the library accepts
    /// (greater than 0; its form allows 0.05 to 20).
    static let depthPerPassRange: ClosedRange<Double> = 0.05...20

    static func clampedDepthPerPass(_ depth: Double) -> Double {
        min(max(depth, depthPerPassRange.lowerBound), depthPerPassRange.upperBound)
    }

    /// The adaptive load in mm for the current tool, which is what the library takes. Also the
    /// read-out in the panel.
    var adaptiveLoadMM: Double {
        Double(tool.toolDiameter) * operation.pocketAdaptiveLoadPercent / 100
    }

    /// The stepover as a fraction of the tool diameter, which is what the library takes.
    var stepOverFraction: Double {
        stepOverPercent / 100
    }

    /// Read-out only: the distance between passes in mm for the current tool.
    var stepOverMM: Double {
        Double(tool.toolDiameter) * stepOverFraction
    }

    /// A facing toolpath set to cover the whole stock; the selected shapes are ignored.
    var cutsWholeStock: Bool {
        operation.kind == .facing && operation.facingWholeStock
    }

    /// Whether there is anything to cut: selected shapes, or the whole stock.
    var hasGeometry: Bool {
        !targets.isEmpty || cutsWholeStock
    }

    /// How far the tool goes down from the top of the stock (or from Start Z when that is
    /// lower), mm. What a single full-depth pass would cut.
    var cutDepth: Double {
        abs(endZ - min(startZ, 0))
    }

    /// Facing deeper than this (mm) in one pass is hard on the tool and the machine.
    static let facingSinglePassWarningDepth = 1.0

    /// A contour with a lead-in whose entry is a ramp or helix: the library refuses that
    /// (the entry already eases the tool in), so the panel flags it and holds back Preview.
    /// Mirrors `ToolpathGenerator.makeEntry`: only an enabled, non-"None" ramp counts.
    var leadInConflictsWithEntry: Bool {
        operation.kind == .contour
            && operation.contourLeadIn != nil
            && ramping.enabled
            && ramping.type != .none
    }

    /// The tool's V-bit included angle in degrees, if it has a tip angle.
    var toolTipAngle: Double? {
        guard let angle = tool.tipAngle.map({ Double($0) }), angle > 0 else {
            return nil
        }
        return angle
    }

    /// How deep a chamfer cuts, mm: the fixed depth when one is set, otherwise what the V-bit's
    /// angle gives for the width (the flank runs `width` sideways for `width / tan(angle / 2)`
    /// down). `nil` when the tool has no tip angle, so the depth can't be worked out.
    var chamferResolvedDepth: Double? {
        if operation.chamferUsesDepth {
            return operation.chamferDepth
        }
        guard let angle = toolTipAngle else {
            return nil
        }
        return operation.chamferWidth / tan(angle / 2 * .pi / 180)
    }

    /// Why the picked tool can't do the operation, if it can't. These are the cases the
    /// library would otherwise only refuse at Preview (see `ToolpathGenerator.message`).
    /// Whether a tool is a thread mill isn't known to the app (`Tool.type` isn't mapped),
    /// so a thread mill can't be checked here.
    var toolCompatibilityWarning: String? {
        let diameter = Double(tool.toolDiameter)
        switch operation.kind {
            case .chamfer:
                if toolTipAngle == nil && !operation.chamferUsesDepth {
                    return "A chamfer needs a V-bit: this tool has no tip angle. Pick a V-bit, or turn on Depth Override."
                }
            case .counterbore:
                if diameter > 0 && operation.counterboreDiameter <= diameter {
                    return String(format: "The counterbore diameter (%.2f mm) must be larger than the tool (Ø%.2f mm).",
                                  operation.counterboreDiameter, diameter)
                }
            case .boring, .threadMilling, .contour, .pocket, .facing, .slotting, .engrave, .drilling:
                break
        }
        return nil
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

        // Projects saved when the adaptive load was in mm: convert it like the stepover above.
        if let mm = operation.legacyAdaptiveLoadMM {
            let diameter = Double(tool.toolDiameter)
            if diameter > 0 {
                operation.pocketAdaptiveLoadPercent = Self.clampedAdaptiveLoad(mm / diameter * 100)
            }
            operation.legacyAdaptiveLoadMM = nil
        }

        // Absent on projects saved before defaults existed: nothing counts as edited, so those
        // projects' values are only replaced if the operation is changed.
        editedFields = try c.decodeIfPresent(Set<ToolpathField>.self, forKey: .editedFields) ?? []
    }
}
