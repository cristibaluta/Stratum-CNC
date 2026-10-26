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
import StratumCAM

struct OperationSettings: Codable, Hashable {

    var kind: OperationKind = .contour
    var direction: CutDirectionOption = .climb

    // Pocket
    var pocketPattern: PocketPattern = .offset
    var pocketSpiral: SpiralOrder = .outsideIn// TODO: reuse model from stratum cam
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
    var chamferSide: SC.CutSide = .outside

    // Thread mill
    var threadTargetDiameter: Double = 3
    var threadPitch: Double = 0.5
    var threadRadialPasses: Int = 3
    var threadIsInternal: Bool = true
    var threadHandedness: ThreadHandedness = .rightHand

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
        chamferSide = try c.decodeIfPresent(SC.CutSide.self, forKey: .chamferSide) ?? d.chamferSide
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
