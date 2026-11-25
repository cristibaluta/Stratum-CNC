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

    /// The tool in full, as it is in the project's `tools.json`. The toolpath file keeps only its
    /// id (`toolID`); the full tool is looked up when the file is read (see `CodingUserInfoKey.projectTools`).
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
    /// The high travel height (mm): where the tool starts and ends and rapids between cuts far apart.
    var safeZ: Double
    /// The low travel height (mm) for the hops between passes. Never above `safeZ` (see `ToolpathGenerator.makeSettings`).
    var retractZ: Double = 1
    /// How far above Start Z (mm, positive) the entry starts: the tool rapids down to here, then
    /// enters. A ramp or helix begins its angled descent from here, in the air; a plunge feeds
    /// straight down from here. 0 starts at Start Z. Relative to Start Z, so it follows it.
    /// Maps to `SC.MachineSettings.startOffset`. Saved as `entryZ` (and, briefly, `rampStartZ`) in older projects.
    var startOffset: Double = 1

    /// The contours (paths on the canvas) this toolpath cuts. Empty until the
    /// user picks some — picked on the canvas while the toolpath is open (see CAMModel.selectedToolpathID).
    var targets: [PathSelection] = []

    /// The STEP model edges this toolpath cuts, picked in the 3D canvas. Cut together with `targets`.
    var stepTargets: [STEPEdgeTarget] = []

    /// The setup (stock orientation) this toolpath is cut in; see `Setup`. `nil` only on projects
    /// saved before setups existed: `CAMModel` puts those in the first setup when it loads them.
    var setupID: UUID? = nil

    /// What the toolpath does (contour, pocket, drill…) and that operation's own options.
    /// `contour` (the contour's side) and `ramping` (the entry) above are used by the
    /// operations that have them; see `SC.MachiningOperation.Kind`.
    var operation = OperationSettings()

    // Explicit so the legacy keys can be read on decode (see init(from:) below)
    // without being written back on encode, and so the tool is saved as its id only.
    private enum CodingKeys: String, CodingKey {
        case id, name, toolID
        case startZ, endZ
        case contour, ramping
        case feedRate, plungeRate, spindleRPM
        case stepDown, stepOverPercent, safeZ, retractZ, startOffset
        case targets, stepTargets, setupID
        case operation
    }
}

extension CodingUserInfoKey {

    /// The project's `tools.json` as `[UUID: Tool]`: what `ToolpathData` turns its saved `toolID`
    /// back into a tool with. Set on the decoder that reads `toolpaths.json`.
    static let projectTools = CodingUserInfoKey(rawValue: "stratum.projectTools")!
}

extension ToolpathData {

    /// The only place the stepover limits live (% of tool diameter), matching what the
    /// generator accepts.
    static let stepOverRange: ClosedRange<Double> = 1...95

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

    /// Stock to leave (mm). Not a library limit (it takes any value of 0 or more): a sane range
    /// for the field, so a typo doesn't leave most of the part standing.
    static let stockToLeaveRange: ClosedRange<Double> = 0...5

    static func clampedStockToLeave(_ mm: Double) -> Double {
        min(max(mm, stockToLeaveRange.lowerBound), stockToLeaveRange.upperBound)
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

    /// Whether the roughing leaves stock: some is set, and the operation (as configured) can
    /// leave it (`requirements.usesAllowance`; a contour cut on the line has no side to leave it on).
    var leavesStock: Bool {
        operation.stockToLeave > 0 && machiningOperation.requirements.usesAllowance
    }

    /// A pocket leaves its floor as well, so the stock to leave has to be less than the depth.
    /// A contour cuts all the way through and only leaves its wall.
    var stockToLeaveExceedsDepth: Bool {
        operation.kind == .pocket && leavesStock && operation.stockToLeave >= abs(endZ) - 1e-9
    }

    /// A facing of the selected shapes that runs past only some sides of their bounding box.
    /// The library only extends every side by the same length, so `ToolpathGenerator.prepare`
    /// hands it the finished rectangle instead.
    var facesOnChosenSides: Bool {
        operation.kind == .facing
            && !operation.facingWholeStock
            && operation.facingExtension > 0
            && !operation.facingSides.isAll
    }

    /// A facing toolpath set to cover the whole stock; the selected shapes are ignored.
    var cutsWholeStock: Bool {
        operation.kind == .facing && operation.facingWholeStock
    }

    /// Whether there is anything to cut: selected shapes, or the whole stock.
    var hasGeometry: Bool {
        if operation.isRest {
            return operation.restSourceID != nil   // its geometry is its source pocket's corners
        }
        return hasSelectedTargets || cutsWholeStock
    }

    /// Shapes or STEP edges are selected.
    var hasSelectedTargets: Bool {
        !targets.isEmpty || !stepTargets.isEmpty
    }

    /// What is selected, for the panels: "2 shapes selected", "3 edges selected".
    var selectionSummary: String {
        var parts: [String] = []
        if !targets.isEmpty {
            parts.append("\(targets.count) shape\(targets.count == 1 ? "" : "s")")
        }
        if !stepTargets.isEmpty {
            parts.append("\(stepTargets.count) edge\(stepTargets.count == 1 ? "" : "s")")
        }

        return parts.isEmpty ? "Click shapes to select" : parts.joined(separator: " + ") + " selected"
    }

    /// How far the tool goes down from the top of the stock (or from Start Z when that is
    /// lower), mm. What a single full-depth pass would cut.
    var cutDepth: Double {
        abs(endZ - min(startZ, 0))
    }

    /// The tool's V-bit included angle in degrees, if it has a tip angle.
    var toolTipAngle: Double? {
        guard let angle = tool.tipAngle.map({ Double($0) }), angle > 0 else {
            return nil
        }
        return angle
    }

    /// How deep a chamfer cuts, mm: what the V-bit's angle gives for the width (the flank runs
    /// `width` sideways for `width / tan(angle / 2)` down). `nil` when the tool has no tip angle,
    /// so the depth can't be worked out.
    var chamferResolvedDepth: Double? {
        guard let angle = toolTipAngle else {
            return nil
        }
        return operation.chamferWidth / tan(angle / 2 * .pi / 180)
    }

    /// The Z range a chamfer works in, calculated (a chamfer has no Start Z or End Z of its own).
    /// It starts from the Z of the selected edge, read from the geometry (`chamferEdgeZ`): for a
    /// top edge that is the bevel's top and the bevel goes down from it by its depth, for a bottom
    /// edge it is the bevel's bottom and the bevel goes up from it. `start` is the bevel's top,
    /// `bevelBottom` its lowest point and `end` the tool TIP at the last pass, which is `tipOffset`
    /// below `bevelBottom`, so with a tip offset it is lower than the finished edge. `nil` for other operations or
    /// when the tool has no tip angle (the depth can't be worked out).
    var chamferZRange: (start: Double, bevelBottom: Double, end: Double)? {
        guard operation.kind == .chamfer, let depth = chamferResolvedDepth else {
            return nil
        }
        let params = SC.ChamferParams(width: operation.chamferWidth,
                                      edge: operation.chamferUsesBottomEdge ? .bottom : .top,
                                      edgeZ: operation.chamferEdgeZ,
                                      tipOffset: operation.chamferTipOffset)
        let range = params.bevelZRange(depth: depth)

        return (start: range.top, bevelBottom: range.bottom, end: range.bottom - operation.chamferTipOffset)
    }

    /// An internal thread the cutter is not smaller than: the library refuses it (as
    /// `SC.Error.toolIncompatible`) because the cutter orbits inside the hole at
    /// (thread - tool) / 2. An external thread always fits.
    var threadToolIsTooLarge: Bool {
        guard operation.kind == .threadMilling, operation.threadIsInternal else {
            return false
        }
        let diameter = Double(tool.toolDiameter)
        let target = operation.threadTargetDiameter
        return diameter > 0 && target > 0 && diameter >= target - 2e-6
    }

    /// What is wrong with the tool for a thread, in a few words: it has to be a thread mill.
    /// `nil` for other operations or when the tool is fine.
    var threadToolProblem: String? {
        guard operation.kind == .threadMilling else {
            return nil
        }
        if let message = toolTypeWarning {
            return message
        }
        if threadToolIsTooLarge {
            return "This thread mill is too large for the thread."
        }
        return nil
    }

    /// A heads-up (not a blocker) when the tool's cutting length is shorter than the depth to mill,
    /// so the cut would run into the shank/holder. `nil` when it reaches, or for operations whose
    /// depth isn't a plain Z range (chamfer, engrave, thread).
    var cuttingLengthWarning: String? {
        switch operation.kind {
            case .chamfer, .engrave, .threadMilling:
                return nil
            default:
                break
        }
        let length = Double(tool.cuttingHeight ?? 0)
        guard length > 0, cutDepth > length + 1e-6 else {
            return nil
        }
        return String(format: "The tool's cutting length (%.2f mm) is less than the depth to mill (%.2f mm).",
                      length, cutDepth)
    }

    /// Why the picked tool can't do the operation, if it can't. These are the cases the
    /// library would otherwise only refuse at Preview (see `ToolpathGenerator.message`).
    var toolCompatibilityWarning: String? {
        let diameter = Double(tool.toolDiameter)

        // First, is it the kind of tool the operation is made for?
        if let message = toolTypeWarning {
            return message
        }

        switch operation.kind {
            case .threadMilling:
                return threadToolProblem
            case .chamfer:
                if toolTipAngle == nil {
                    return "A chamfer needs a V-bit: this tool has no tip angle."
                }
            case .counterbore:
                if diameter > 0 && operation.counterboreDiameter <= diameter {
                    return String(format: "The counterbore diameter (%.2f mm) must be larger than the tool (Ø%.2f mm).",
                                  operation.counterboreDiameter, diameter)
                }
            case .drilling, .boring, .contour, .pocket, .pocket3D, .facing, .slotting, .engrave:
                break
        }
        return nil
    }

    /// Whether the picked tool is a kind the operation is made for. What each operation is
    /// made for is the library's rule (`SC.OperationRequirements.toolTypes`); a tool of another
    /// kind isn't refused, only flagged under the tool.
    private var toolSuitsOperation: Bool {
        machiningOperation.accepts(tool: ToolpathGenerator.makeTool(from: tool, for: operation.kind))
    }

    /// A short note when the picked tool isn't a kind the operation is made for, naming what to pick.
    /// The wording is the app's; whether the tool suits is the library's (see `toolSuitsOperation`).
    var toolTypeWarning: String? {
        guard !toolSuitsOperation else {
            return nil
        }
        if operation.isRest {
            return "A rest operation requires an end mill."
        }
        switch operation.kind {
            case .drilling:      return "Drilling requires a drill bit."
            case .threadMilling: return "Thread milling requires a thread mill bit."
            case .facing:        return "Facing requires an end mill."
            case .pocket:        return "A pocket requires an end mill."
            case .pocket3D:      return "A pocket requires an end mill."
            case .counterbore:   return "A counterbore requires an end mill."
            case .boring:        return "Boring requires an end mill."
            case .contour:       return "A contour requires an end mill."
            case .slotting:      return "A slot requires an end mill."
            case .engrave:       return "Engraving requires an engraving bit or a V-bit."
            case .chamfer:       return "A chamfer requires a V-bit or a chamfer bit."
        }
    }

    /// Keys of older projects: the stepover in mm, and the entry height as `entryZ` or `rampStartZ`.
    private enum LegacyCodingKeys: String, CodingKey {
        case stepOver, entryZ, rampStartZ
    }
}

// Kept in an extension so the compiler-generated memberwise init survives.
extension ToolpathData {

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let toolID = try c.decode(UUID.self, forKey: .toolID)
        let projectTools = decoder.userInfo[.projectTools] as? [UUID: Tool] ?? [:]
        guard let savedTool = projectTools[toolID] else {
            throw DecodingError.dataCorruptedError(forKey: .toolID, in: c,
                                                   debugDescription: "Tool \(toolID) is not in tools.json")
        }
        tool = savedTool
        startZ = try c.decode(Double.self, forKey: .startZ)
        endZ = try c.decode(Double.self, forKey: .endZ)
        contour = try c.decode(SC.CutSide.self, forKey: .contour)
        ramping = try c.decode(RampingSettings.self, forKey: .ramping)
        feedRate = try c.decode(Double.self, forKey: .feedRate)
        plungeRate = try c.decode(Double.self, forKey: .plungeRate)
        spindleRPM = try c.decode(Int.self, forKey: .spindleRPM)
        stepDown = try c.decode(Double.self, forKey: .stepDown)
        safeZ = try c.decode(Double.self, forKey: .safeZ)
        // Projects saved before Retract Z existed used a fixed 1 mm.
        retractZ = try c.decodeIfPresent(Double.self, forKey: .retractZ) ?? 1
        // Projects saved before the rename called it Entry Z, then Ramp start Z.
        let legacyKeys = try decoder.container(keyedBy: LegacyCodingKeys.self)
        startOffset = try c.decodeIfPresent(Double.self, forKey: .startOffset)
            ?? legacyKeys.decodeIfPresent(Double.self, forKey: .rampStartZ)
            ?? legacyKeys.decodeIfPresent(Double.self, forKey: .entryZ)
            ?? 1

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
        stepTargets = try c.decodeIfPresent([STEPEdgeTarget].self, forKey: .stepTargets) ?? []
        setupID = try c.decodeIfPresent(UUID.self, forKey: .setupID)

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
    }
}

extension ToolpathData {

    /// Everything as the synthesized version would write it, except the tool: only its id.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(tool.id, forKey: .toolID)
        try c.encode(startZ, forKey: .startZ)
        try c.encode(endZ, forKey: .endZ)
        try c.encode(contour, forKey: .contour)
        try c.encode(ramping, forKey: .ramping)
        try c.encode(feedRate, forKey: .feedRate)
        try c.encode(plungeRate, forKey: .plungeRate)
        try c.encode(spindleRPM, forKey: .spindleRPM)
        try c.encode(stepDown, forKey: .stepDown)
        try c.encode(stepOverPercent, forKey: .stepOverPercent)
        try c.encode(safeZ, forKey: .safeZ)
        try c.encode(retractZ, forKey: .retractZ)
        try c.encode(startOffset, forKey: .startOffset)
        try c.encode(targets, forKey: .targets)
        try c.encode(stepTargets, forKey: .stepTargets)
        try c.encodeIfPresent(setupID, forKey: .setupID)
        try c.encode(operation, forKey: .operation)
    }
}
