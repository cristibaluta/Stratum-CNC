//
//  ProbeFlow.swift
//  Stratum CNC
//
//  The state and rules of the 3D probing dialog: which step it is on, what is
//  being probed, and where the probe should be jogged to. Pure state;
//  `ProbeSheet` presents it. Same split as `BitChangeFlow` / `BitChangeSheet`.
//
//  Nothing here knows a size. The person jogs the tip to a spot (the dot) and
//  the cycle reaches out from there until it touches, using only the probing
//  settings (search distance, dot distance, side depth).
//
//  Seen from above: X to the right, Y up.
//

import Foundation

struct ProbeFlow: Equatable {

    enum Step: Int, CaseIterable, Equatable {
        case what
        case tool
        case position
        case probe
        case result

        var title: String {
            switch self {
                case .what: "What"
                case .tool: "Probe"
                case .position: "Position"
                case .probe: "Run"
                case .result: "Result"
            }
        }
    }

    private(set) var step: Step = .what

    /// Z or XY.
    var kind: ProbeKind = .point
    /// Which XY feature. Only used when `kind == .point`.
    var feature: ProbeFeature = .bossCorner
    /// Which corner, for the two corner features.
    var corner: ProbePoint = .bottomLeft

    // MARK: What is being probed

    /// True when XY is probed from inside, moving out (a pocket).
    var isInside: Bool { kind == .point && feature.isInside }

    /// True when XY finds the middle of the feature.
    var isCenter: Bool { kind == .point && feature.isCenter }

    /// Whether the drawing offers the four corners to choose from.
    var choosesCorner: Bool { kind == .point && !feature.isCenter }

    /// The point actually probed.
    var effectivePoint: ProbePoint { feature.isCenter ? .center : corner }

    // MARK: Choosing

    /// The sides the chosen point needs touched, in the order they are
    /// probed. A corner is two sides, the center four.
    var sides: [ProbeEdge] {
        guard kind == .point else { return [] }
        let chosen = effectivePoint
        if chosen.isCenter { return [.left, .right, .bottom, .top] }
        var result: [ProbeEdge] = []
        if chosen.column < 0 { result.append(.left) }
        if chosen.column > 0 { result.append(.right) }
        if chosen.row < 0 { result.append(.bottom) }
        if chosen.row > 0 { result.append(.top) }
        return result
    }

    /// The way the probe moves to touch `side`, and the axis it moves on.
    /// From outside the probe moves toward the boss (+ to reach the left or
    /// bottom side); from inside it moves out toward the wall (the opposite).
    func probeDirection(for side: ProbeEdge) -> (axis: ProbeAxis, direction: Int) {
        let towardPositive = side == .left || side == .bottom
        return (side.axis, (!isInside) == towardPositive ? 1 : -1)
    }

    /// XY first touches the top (or the pocket floor) to know the height: the
    /// sides are touched at a depth below it.
    var probesZFirst: Bool { kind != .zSurface }

    /// Whether Z0 is written during the cycle. The Z mode always sets it. In
    /// XY it is set on the top that was touched, but not on a pocket floor.
    func setsZ(settings: ProbeSettings) -> Bool {
        if kind == .zSurface { return true }
        return settings.setsZ && !isInside
    }

    // MARK: Moving through the steps

    var canAdvance: Bool {
        switch step {
            case .what, .tool, .position, .probe: true
            case .result: false
        }
    }

    mutating func advance() {
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    mutating func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: Where to jog

    /// What the person has to do on the position step.
    func instructions(settings: ProbeSettings) -> [String] {
        var steps = ["Put the \(settings.probe.title.lowercased()) (T\(settings.probeTool)) in the spindle and check that it triggers when you touch the tip."]
        let inset = Self.mm(settings.startInset)
        let reach = Self.mm(settings.searchDistance)

        switch kind {
            case .zSurface:
                steps.append("Jog the tip above the surface you want as Z0: the top of the stock, or the floor of a pocket.")
                steps.append("The probe moves straight down until it touches, up to \(reach) mm. Z0 is set there.")
                return steps

            case .point:
                let title = effectivePoint.title(inside: isInside).lowercased()
                switch feature {
                    case .bossCorner:
                        steps.append("Jog the tip above the boss, over its \(title), \(inset) mm from both sides. Keep it above the boss.")
                    case .pocketCorner:
                        steps.append("Jog the tip above the pocket, over its \(title), \(inset) mm from both walls. Keep it above the stock so it can drop in.")
                    case .bossCenter:
                        steps.append("Jog the tip above the boss, roughly in the middle. Keep it above the boss.")
                    case .pocketCenter:
                        steps.append("Jog the tip above the pocket, roughly in the middle. Keep it above the stock so it can drop in.")
                }

                if feature.isCenter {
                    steps.append("Every side must be within \(reach) mm of the dot. For something bigger, raise the search distance in Settings.")
                } else {
                    steps.append("Stay within about 2 mm of the dot in X and Y. The height does not need to be exact.")
                }

                if isInside {
                    steps.append("The floor is touched first, only to know the height (it must be within \(reach) mm below the tip). The walls are then touched \(Self.mm(wallHeight(settings: settings))) mm above it.")
                } else {
                    let depth = Self.mm(settings.edgeDepth)
                    let outside = Self.mm(settings.outsideClearance)
                    steps.append("The top is touched first. The sides are then touched \(depth) mm below it, starting \(outside) mm outside the edge.")
                }
                return steps
        }
    }

    /// How far above the pocket's floor its walls are touched.
    func wallHeight(settings: ProbeSettings) -> Double {
        settings.edgeDepth
    }

    /// 10 → "10", 1.5 → "1.5".
    static func mm(_ value: Double) -> String {
        String(format: "%g", value)
    }

    // MARK: Text

    /// Where the work origin ends up, for the summary line.
    var originDescription: String {
        switch kind {
            case .zSurface:
                return "Sets Z0 on the surface under the tip."
            case .point:
                let thing = feature.thing
                let zText = isInside ? "" : ", and Z0 on its top"
                if feature.isCenter {
                    return "Sets X0 Y0 at the center of the \(thing)\(zText)."
                }
                return "Sets X0 Y0 at the \(corner.title(inside: isInside).lowercased()) of the \(thing)\(zText)."
        }
    }

    /// One or two sentences on what will happen, shown on the first step.
    var summary: String {
        switch kind {
            case .zSurface:
                return "The probe moves down until it touches and sets Z0 there. It works on the top of the stock and on the floor of a pocket."
            case .point:
                var text = originDescription
                if isInside {
                    text += " The floor is touched first to know the height; Z0 is left alone."
                } else {
                    text += " The top is touched first, because the sides are touched below it."
                }
                return text
        }
    }
}
