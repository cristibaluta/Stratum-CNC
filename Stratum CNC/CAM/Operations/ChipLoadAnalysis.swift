//
//  ChipLoadAnalysis.swift
//  Stratum CNC
//
//  What a feed / RPM / flutes combination does in the cut: the feed it gives, how thick the
//  chip really is once a light stepover thins it, how much material it removes, and how
//  close it is to rubbing (too thin a chip leaves the heat in the tool). Used by the feed
//  calculator popover; no UI in here.
//
//  Units: lengths in mm, feed in mm/min, surface speed in m/min.
//

import SwiftUI

struct ChipLoadAnalysis {

    /// Chip load: how much each flute takes per revolution, mm per tooth.
    var chipLoad: Double
    var flutes: Int
    var rpm: Int
    var toolDiameter: Double
    /// Radial engagement as a fraction of the diameter. `nil` when the operation has no
    /// stepover (a contour): the engagement is then taken as half the tool, where the chip
    /// is not thinned.
    var stepOverFraction: Double?
    /// Depth of cut per pass, mm; only used for the removal rate.
    var stepDown: Double
    /// Chip load a preset of the tool recommends, mm per tooth, if it has one.
    var recommendedChipLoad: Double?
    /// Cutting speed a preset of the tool recommends, m/min, if it has one.
    var recommendedSurfaceSpeed: Double?

    // MARK: Derived numbers

    /// mm/min, rounded to a whole number like a feed you would type.
    var feed: Double {
        (chipLoad * Double(flutes) * Double(rpm)).rounded()
    }

    /// Radial engagement as a fraction of the diameter, 0.01...1.
    var engagement: Double {
        min(max(stepOverFraction ?? 0.5, 0.01), 1)
    }

    /// How much of the nominal chip load is left at the thickest point of the chip. Up to
    /// half the diameter of engagement the chip is the full chip load; with less, the tooth
    /// leaves the cut before the chip has grown that thick: 2·√(ae/D · (1 − ae/D)).
    var chipThinningFactor: Double {
        engagement >= 0.5 ? 1 : 2 * (engagement * (1 - engagement)).squareRoot()
    }

    /// The thickest part of the chip, mm.
    var chipThickness: Double {
        chipLoad * chipThinningFactor
    }

    /// Cutting speed at the edge of the tool, m/min.
    var surfaceSpeed: Double {
        Double.pi * toolDiameter * Double(rpm) / 1000
    }

    /// Material taken off per minute, cm³/min: feed × stepover × depth.
    var removalRate: Double {
        feed * (engagement * toolDiameter) * stepDown / 1000
    }

    // MARK: Heat

    /// Below this chip thickness the tool rubs more than it cuts. A preset's chip load
    /// is the middle of the good range; without one, a rough range that scales with the
    /// diameter (about 0.4 % of it at the low end, 1.7 % at the high end: 0.024...0.1 mm
    /// for a 6 mm tool, 0.004...0.017 mm for a 1 mm one).
    private var minimumChip: Double {
        (recommendedChipLoad.map { $0 * 0.4 }) ?? toolDiameter * 0.004
    }

    /// Above this the tool is being asked for too much per tooth.
    private var maximumChip: Double {
        (recommendedChipLoad.map { $0 * 1.6 }) ?? toolDiameter * 0.0167
    }

    /// Whether there is enough to say anything about the cut.
    var isComplete: Bool {
        chipLoad > 0 && flutes > 0 && rpm > 0 && toolDiameter > 0
    }

    /// 0 (the chip carries the heat away) ... 1 (the tool is rubbing and cooking).
    /// Two things raise it: a chip thinner than the tool can cut cleanly, and a surface
    /// speed beyond what the preset recommends. The worse of the two counts.
    var heat: Double {
        guard isComplete else {
            return 0
        }
        // Fully cool from 1.5× the minimum chip up, fully hot at half of it.
        let thinness = min(max((1.5 - chipThickness / minimumChip), 0), 1)
        // Fully hot at 1.5× the recommended speed.
        var speed = 0.0
        if let recommended = recommendedSurfaceSpeed, recommended > 0 {
            speed = min(max(surfaceSpeed / recommended - 1, 0) / 0.5, 1)
        }
        return max(thinness, speed)
    }

    /// The chip is thicker than the tool should take.
    var isHeavy: Bool {
        isComplete && chipThickness > maximumChip
    }

    enum Verdict {
        case incomplete, good, warm, hot, heavy
    }

    var verdict: Verdict {
        guard isComplete else { return .incomplete }
        if isHeavy { return .heavy }
        if heat >= 0.66 { return .hot }
        if heat >= 0.33 { return .warm }
        return .good
    }

    /// One line on what the numbers mean for the tool.
    var message: String {
        switch verdict {
            case .incomplete:
                return "Fill in the chip load, flutes and spindle speed."
            case .good:
                return "The chip is thick enough to carry the heat away."
            case .warm:
                return speedIsTheCause
                    ? "A little fast for this tool: the edge is getting warm."
                    : "The chip is getting thin: the tool starts to rub and warm up."
            case .hot:
                return speedIsTheCause
                    ? "Too fast for this tool: expect heat, wear and burn marks."
                    : "Too thin: the tool rubs instead of cutting. Expect heat, wear and burn marks. Feed faster or slow the spindle."
            case .heavy:
                return "Heavy chip: the tool may deflect, chatter or break. Feed slower or add flutes."
        }
    }

    /// The speed, not the chip, is what makes it hot.
    private var speedIsTheCause: Bool {
        guard let recommended = recommendedSurfaceSpeed, recommended > 0 else {
            return false
        }
        let speed = min(max(surfaceSpeed / recommended - 1, 0) / 0.5, 1)
        let thinness = min(max((1.5 - chipThickness / minimumChip), 0), 1)
        return speed > thinness
    }

    /// The chip thinning note, when the stepover is light enough to matter.
    var thinningNote: String? {
        guard isComplete, stepOverFraction != nil, chipThinningFactor < 0.9 else {
            return nil
        }
        return "Light stepover thins the chip: \(Self.format(chipThickness)) mm instead of \(Self.format(chipLoad)). A higher chip load makes up for it."
    }

    /// The color for the state: green while it cuts, through yellow and orange, to red when
    /// it is too hot. A heavy chip is not heat, so it keeps a neutral purple.
    var tint: Color {
        isHeavy ? Color(hue: 0.75, saturation: 0.55, brightness: 0.95) : HeatColor.color(for: heat)
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)).locale(Locale(identifier: "en_US")))
    }
}

enum HeatColor {
    /// 0 is green, 0.5 amber, 1 red.
    static func color(for heat: Double) -> Color {
        let heat = min(max(heat, 0), 1)
        return Color(hue: 0.36 * (1 - heat), saturation: 0.85, brightness: 0.95)
    }
}
