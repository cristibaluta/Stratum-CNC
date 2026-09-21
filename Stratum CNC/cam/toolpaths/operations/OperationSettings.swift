//
//  OperationSettings.swift
//  Stratum CNC
//
//  What a toolpath *does* (contour, pocket, drill…) and the options that only make sense
//  for that operation. Mirrors StratumCAM's `SC.MachiningOperation`; the translation lives in
//  `ToolpathGenerator.makeOperation(from:)`.
//
//  All operations' options are kept side by side in one flat struct, so switching the
//  operation back and forth in the UI doesn't lose what was typed for the other ones.
//

import Foundation

// MARK: - Operation kind

enum OperationKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case contour
    case pocket
    case facing
    case slotting
    case engrave
    case drilling
    case counterbore
    case boring
    case threadMilling
    case chamfer

    var id: String { rawValue }

    /// The order and grouping used by the picker menu.
    static let groups: [[OperationKind]] = [
        [.contour, .pocket, .facing, .slotting, .engrave],
        [.drilling, .counterbore, .boring, .threadMilling],
        [.chamfer]
    ]

    var title: String {
        switch self {
        case .contour:       return "Contour"
        case .pocket:        return "Pocket"
        case .facing:        return "Facing"
        case .slotting:      return "Slot"
        case .engrave:       return "Engrave"
        case .drilling:      return "Drill"
        case .counterbore:   return "Counterbore"
        case .boring:        return "Bore"
        case .threadMilling: return "Thread mill"
        case .chamfer:       return "Chamfer"
        }
    }

    /// SF Symbol shown next to the title in the picker.
    var symbol: String {
        switch self {
        case .contour:       return "square.dashed"
        case .pocket:        return "square.inset.filled"
        case .facing:        return "rectangle.compress.vertical"
        case .slotting:      return "capsule"
        case .engrave:       return "pencil.tip"
        case .drilling:      return "smallcircle.filled.circle"
        case .counterbore:   return "circle.circle"
        case .boring:        return "circle.dashed"
        case .threadMilling: return "screwdriver"
        case .chamfer:       return "diamond"
        }
    }

    /// What to select on the canvas for this operation.
    var selectionHint: String? {
        switch self {
        case .contour:
            return nil
        case .pocket:
            return "Select closed shapes to clear."
        case .facing:
            return "Covers the bounding box of the selection — select the finished part's outline."
        case .slotting:
            return nil   // depends on the slot source, see OperationOptionsView
        case .engrave:
            return "Follows the selected lines and text."
        case .drilling:
            return "Drills at a selected point or circle, or at the centre of any closed shape."
        case .counterbore, .boring:
            return "Select a point or a closed circle per hole (DXF and drill-file circles work; SVG circles are stored as lines and aren't recognised)."
        case .threadMilling:
            return "Select the existing hole as a closed circle (DXF and drill-file circles work; SVG circles aren't recognised)."
        case .chamfer:
            return "Bevels the selected edges. Needs a V-bit, unless you give an explicit depth."
        }
    }

    // MARK: Which generic controls apply

    /// Steps down in several passes by the general Stepdown. Facing, drilling, boring and
    /// chamfering are a single pass; a slot has its own depth per pass; a thread steps by its pitch.
    var usesStepdown: Bool {
        switch self {
        case .contour, .pocket, .engrave, .counterbore: return true
        default: return false
        }
    }

    var usesStepover: Bool {
        switch self {
        case .pocket, .counterbore: return true
        default: return false
        }
    }

    /// The counterbore has its own depth and a chamfer's depth comes from its width and the
    /// V-bit's angle, so the general End Z field is hidden for them.
    var usesEndZ: Bool {
        switch self {
        case .counterbore, .chamfer: return false
        default: return true
        }
    }
}

// MARK: - Small option enums

enum CutDirectionOption: String, CaseIterable, Codable, Hashable {
    case climb = "Climb"
    case conventional = "Conventional"
}

enum ThreadHandedness: String, CaseIterable, Codable, Hashable {
    case rightHand = "Right-hand"
    case leftHand = "Left-hand"
}

/// How a pocket is cleared. StratumCAM also has `.adaptive`, but its engine still stops with
/// `fatalError("Not implemented yet")` for it, so it isn't offered here.
enum PocketPattern: String, CaseIterable, Codable, Hashable {
    case offset = "Offset"
    case raster = "Raster"
    case spiral = "Spiral"
    case trochoidal = "Trochoidal"
}

enum SpiralOrder: String, CaseIterable, Codable, Hashable {
    case outsideIn = "Outside in"
    case insideOut = "Inside out"
}

/// What the selected shape means for a slot.
enum SlotSource: String, CaseIterable, Codable, Hashable {
    /// The drawn slot walls: a straight-sided rectangle as wide as the tool.
    case outline = "Slot outline"
    /// The line the tool centre follows.
    case centerline = "Centre line"
}

enum ChamferSide: String, CaseIterable, Codable, Hashable {
    case outside = "Outside"
    case inside = "Inside"
}

// MARK: - Options

struct OperationSettings: Codable, Hashable {

    var kind: OperationKind = .contour

    // Contour · Pocket · Facing · Counterbore
    // (the contour's inside/outside/on-line side stays in `ToolpathData.contour`,
    //  the entry strategy in `ToolpathData.ramping`)
    var direction: CutDirectionOption = .climb

    // Pocket
    var pocketPattern: PocketPattern = .offset
    var pocketSpiral: SpiralOrder = .outsideIn
    /// Trochoidal forward pitch per loop, as a percentage of the tool radius.
    var pocketTrochoidalPitch: Double = 50

    // Facing
    /// How far the passes run past the selection's bounding box, mm.
    var facingExtension: Double = 1

    // Slot
    var slotSource: SlotSource = .outline
    var slotDepthPerPass: Double = 0.5

    // Drill
    var drillUsesPecking: Bool = false
    var drillPeckDepth: Double = 1

    // Counterbore
    var counterboreDiameter: Double = 8
    var counterboreDepth: Double = 3

    // Bore
    var boreTargetDiameter: Double = 6
    var boreUsesDwell: Bool = false
    /// Seconds.
    var boreDwellTime: Double = 0.5
    var boreShiftRetract: Bool = true

    // Chamfer
    /// Horizontal width of the bevel, mm.
    var chamferWidth: Double = 0.5
    /// Cut to a fixed depth instead of the one the V-bit's angle gives for `chamferWidth`.
    var chamferUsesDepth: Bool = false
    var chamferDepth: Double = 0.5
    var chamferSide: ChamferSide = .outside

    // Thread mill
    var threadPitch: Double = 1
    var threadIsInternal: Bool = true
    var threadHandedness: ThreadHandedness = .rightHand
    var threadRadialPasses: Int = 2
    var threadTargetDiameter: Double = 6

    private enum CodingKeys: String, CodingKey {
        case kind, direction
        case pocketPattern, pocketSpiral, pocketTrochoidalPitch
        case facingExtension
        case slotSource, slotDepthPerPass
        case chamferWidth, chamferUsesDepth, chamferDepth, chamferSide
        case drillUsesPecking, drillPeckDepth
        case counterboreDiameter, counterboreDepth
        case boreTargetDiameter, boreUsesDwell, boreDwellTime, boreShiftRetract
        case threadPitch, threadIsInternal, threadHandedness, threadRadialPasses, threadTargetDiameter
    }
}

// In an extension so the memberwise / default initializers survive.
extension OperationSettings {

    /// Every key is optional, so projects saved before an option existed still open,
    /// and options can be added later without breaking saved projects.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = OperationSettings()

        kind = try c.decodeIfPresent(OperationKind.self, forKey: .kind) ?? d.kind
        direction = try c.decodeIfPresent(CutDirectionOption.self, forKey: .direction) ?? d.direction
        pocketPattern = try c.decodeIfPresent(PocketPattern.self, forKey: .pocketPattern) ?? d.pocketPattern
        pocketSpiral = try c.decodeIfPresent(SpiralOrder.self, forKey: .pocketSpiral) ?? d.pocketSpiral
        pocketTrochoidalPitch = try c.decodeIfPresent(Double.self, forKey: .pocketTrochoidalPitch) ?? d.pocketTrochoidalPitch
        facingExtension = try c.decodeIfPresent(Double.self, forKey: .facingExtension) ?? d.facingExtension
        slotSource = try c.decodeIfPresent(SlotSource.self, forKey: .slotSource) ?? d.slotSource
        chamferWidth = try c.decodeIfPresent(Double.self, forKey: .chamferWidth) ?? d.chamferWidth
        chamferUsesDepth = try c.decodeIfPresent(Bool.self, forKey: .chamferUsesDepth) ?? d.chamferUsesDepth
        chamferDepth = try c.decodeIfPresent(Double.self, forKey: .chamferDepth) ?? d.chamferDepth
        chamferSide = try c.decodeIfPresent(ChamferSide.self, forKey: .chamferSide) ?? d.chamferSide
        slotDepthPerPass = try c.decodeIfPresent(Double.self, forKey: .slotDepthPerPass) ?? d.slotDepthPerPass
        drillUsesPecking = try c.decodeIfPresent(Bool.self, forKey: .drillUsesPecking) ?? d.drillUsesPecking
        drillPeckDepth = try c.decodeIfPresent(Double.self, forKey: .drillPeckDepth) ?? d.drillPeckDepth
        counterboreDiameter = try c.decodeIfPresent(Double.self, forKey: .counterboreDiameter) ?? d.counterboreDiameter
        counterboreDepth = try c.decodeIfPresent(Double.self, forKey: .counterboreDepth) ?? d.counterboreDepth
        boreTargetDiameter = try c.decodeIfPresent(Double.self, forKey: .boreTargetDiameter) ?? d.boreTargetDiameter
        boreUsesDwell = try c.decodeIfPresent(Bool.self, forKey: .boreUsesDwell) ?? d.boreUsesDwell
        boreDwellTime = try c.decodeIfPresent(Double.self, forKey: .boreDwellTime) ?? d.boreDwellTime
        boreShiftRetract = try c.decodeIfPresent(Bool.self, forKey: .boreShiftRetract) ?? d.boreShiftRetract
        threadPitch = try c.decodeIfPresent(Double.self, forKey: .threadPitch) ?? d.threadPitch
        threadIsInternal = try c.decodeIfPresent(Bool.self, forKey: .threadIsInternal) ?? d.threadIsInternal
        threadHandedness = try c.decodeIfPresent(ThreadHandedness.self, forKey: .threadHandedness) ?? d.threadHandedness
        threadRadialPasses = try c.decodeIfPresent(Int.self, forKey: .threadRadialPasses) ?? d.threadRadialPasses
        threadTargetDiameter = try c.decodeIfPresent(Double.self, forKey: .threadTargetDiameter) ?? d.threadTargetDiameter
    }
}
