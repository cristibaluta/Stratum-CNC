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
    /// Adaptive clearing: the radial engagement the tool is kept at, as a percentage of the
    /// tool diameter (like the stepover). The library takes mm: see `ToolpathData.adaptiveLoadMM`.
    var pocketAdaptiveLoadPercent: Double = 25
    /// Only set while decoding a project saved when the load was in mm; `ToolpathData` converts
    /// it with the saved tool's diameter and clears it. Never encoded.
    var legacyAdaptiveLoadMM: Double? = nil

    // Contour
    /// Holding tabs left in the cut, in the order the form lists them.
    var contourTabs: [HoldingTabSettings] = []
    /// The approach before the cut and the move off it afterwards. `nil` = none (the tool
    /// goes straight in / out). A lead-in can't be combined with a ramp or helix entry,
    /// see `ToolpathData.leadInConflictsWithEntry`.
    var contourLeadIn: LeadInOutSettings? = nil
    var contourLeadOut: LeadInOutSettings? = nil

    // Facing
    /// How far the passes run past the selection's bounding box, mm.
    var facingExtension: Double = 1
    /// Face the whole stock instead of the bounding box of the selected shapes. The selected
    /// shapes are kept (so switching back restores them) but ignored while this is on.
    var facingWholeStock: Bool = false

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

    /// Keys of older projects.
    private enum LegacyCodingKeys: String, CodingKey {
        case pocketAdaptiveLoad
    }

    private enum CodingKeys: String, CodingKey {
        case kind, direction
        case pocketPattern, pocketSpiral, pocketTrochoidalPitch, pocketAdaptiveLoadPercent
        case contourTabs, contourLeadIn, contourLeadOut
        case facingExtension, facingWholeStock
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
        if let percent = try c.decodeIfPresent(Double.self, forKey: .pocketAdaptiveLoadPercent) {
            pocketAdaptiveLoadPercent = percent
        } else {
            // Projects saved when the load was in mm
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            legacyAdaptiveLoadMM = try legacy.decodeIfPresent(Double.self, forKey: .pocketAdaptiveLoad)
        }
        contourTabs = try c.decodeIfPresent([HoldingTabSettings].self, forKey: .contourTabs) ?? d.contourTabs
        contourLeadIn = try c.decodeIfPresent(LeadInOutSettings.self, forKey: .contourLeadIn) ?? d.contourLeadIn
        contourLeadOut = try c.decodeIfPresent(LeadInOutSettings.self, forKey: .contourLeadOut) ?? d.contourLeadOut
        facingExtension = try c.decodeIfPresent(Double.self, forKey: .facingExtension) ?? d.facingExtension
        facingWholeStock = try c.decodeIfPresent(Bool.self, forKey: .facingWholeStock) ?? d.facingWholeStock
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

/// A contour's lead-in or lead-out: the app's own Codable copy of `SC.LeadInOut`.
struct LeadInOutSettings: Codable, Hashable {

    enum Style: Codable, Hashable {
        /// A straight run, mm.
        case linear(length: Double)
        /// A quarter-circle-like arc: radius in mm, sweep in degrees.
        case arc(radius: Double, sweepAngleDegrees: Double)
    }

    var style: Style
    /// mm/min.
    var feedRate: Double

    init(style: Style, feedRate: Double) {
        self.style = style
        self.feedRate = feedRate
    }

    init(_ leadInOut: SC.LeadInOut) {
        switch leadInOut.style {
            case .linear(let length):
                style = .linear(length: length)
            case .arc(let radius, let sweep):
                style = .arc(radius: radius, sweepAngleDegrees: sweep)
        }
        feedRate = leadInOut.feedRate
    }

    var libraryLeadInOut: SC.LeadInOut {
        switch style {
            case .linear(let length):
                return SC.LeadInOut(style: .linear(length: length), feedRate: feedRate)
            case .arc(let radius, let sweep):
                return SC.LeadInOut(style: .arc(radius: radius, sweepAngleDegrees: sweep), feedRate: feedRate)
        }
    }
}

/// One holding tab of a contour: the app's own Codable copy of `SC.HoldingTab`
/// (whose id is new every time it is built). The `id` here only identifies the row in the
/// editor and isn't saved.
struct HoldingTabSettings: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Where along the contour the tab sits, 0...1.
    var positionRatio: Double
    /// mm.
    var width: Double
    /// mm, measured up from the bottom of the cut.
    var height: Double

    /// The ranges `SC.MachiningOperation.formFields` gives these values.
    static let positionRange: ClosedRange<Double> = 0...1
    static let widthRange: ClosedRange<Double> = 1...20
    static let heightRange: ClosedRange<Double> = 0.1...10

    private enum CodingKeys: String, CodingKey {
        case positionRatio, width, height
    }

    init(positionRatio: Double, width: Double, height: Double) {
        self.positionRatio = positionRatio
        self.width = width
        self.height = height
    }

    init(_ tab: SC.HoldingTab) {
        self.init(positionRatio: tab.positionRatio, width: tab.width, height: tab.height)
    }

    /// A tab with the library's default size, put in the middle of the largest gap between
    /// the existing ones so they don't pile up at the same spot.
    static func new(after tabs: [HoldingTabSettings]) -> HoldingTabSettings {
        var tab = HoldingTabSettings(SC.HoldingTab(positionRatio: 0.5))
        let positions = ([0.0] + tabs.map(\.positionRatio).sorted() + [1.0])
        var best = (gap: 0.0, middle: 0.5)
        for (a, b) in zip(positions, positions.dropFirst()) where b - a > best.gap {
            best = (b - a, (a + b) / 2)
        }
        tab.positionRatio = best.middle
        return tab
    }

    var libraryTab: SC.HoldingTab {
        var tab = SC.HoldingTab(positionRatio: positionRatio)
        tab.width = width
        tab.height = height
        return tab
    }
}
