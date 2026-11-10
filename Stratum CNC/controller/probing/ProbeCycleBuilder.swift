//
//  ProbeCycleBuilder.swift
//  Stratum CNC
//
//  Turns "what to probe" + the settings + the stock into the list of steps a
//  cycle runs. Pure: no machine, no UI, so every sign and distance is tested.
//
//  Nothing here knows a size. Every distance comes from the settings or from
//  positions the machine just reported:
//    Z: touch down on whatever is under the tip.
//    boss (outside): touch the top, then each side from outside, lowering
//      beside the boss first.
//    pocket (inside): touch the floor to know the height, rise a little, then
//      touch each wall from inside, moving out; finally go back up to the
//      height the cycle started at.
//  A corner uses the dot's distance from its two sides. A center reaches out
//  by the search distance in each direction and returns to the dot using the
//  start position the machine reported.
//
//  The cycle starts with the probe tip above the dot and moves RELATIVE (G91)
//  from there, so it does not depend on the work offset. Positions that matter
//  are read back in machine coordinates and the origin is written afterwards
//  from them.
//

import Foundation

struct ProbeCycleBuilder {

    let flow: ProbeFlow
    let settings: ProbeSettings
    /// The command that makes the current Z read zero
    /// (`SL.Session.zeroCommand(z: true)`).
    let zeroZCommand: String

    /// Probe toward the stock; an error if nothing is touched.
    static let probe = "G38.2"
    /// Probe, but no error if nothing is touched. Used to lower beside the
    /// stock, where touching something is the failure.
    static let probeQuiet = "G38.3"

    // MARK: Problems

    /// Reasons the cycle can't run with this choice and these settings.
    static func problems(flow: ProbeFlow, settings: ProbeSettings) -> [String] {
        var result = settings.problems
        guard flow.kind == .point else { return result }

        if settings.edgeDepth <= 0 {
            result.append("The side depth must be above 0.")
        }
        if flow.isInside, !flow.isCenter, settings.startInset <= settings.ballRadius + 0.5 {
            result.append("The dot is too close to the walls for the probe ball. Raise the dot distance in Settings.")
        }
        return result
    }

    // MARK: Build

    func build() -> [ProbeStepPlan] {
        var steps = [prepare]

        switch flow.kind {
            case .zSurface:
                steps += topSteps(title: "Touch the surface")

            case .point:
                if flow.isInside {
                    steps += floorSteps()
                    steps += flow.isCenter ? centerSteps() : pocketWallSteps(pass: 0, origin: nil)
                    steps.append(leavePocket)
                } else {
                    steps += topSteps(title: "Touch the top")
                    steps += flow.isCenter ? centerSteps() : stockSideSteps(pass: 0, origin: nil)
                }
        }

        steps.append(finish)
        return steps
    }

    // MARK: Numbers

    private var radius: Double { settings.ballRadius }

    /// 10 → "10", 1.5 → "1.5", −0.0004 → "0".
    static func number(_ value: Double) -> String {
        value.trimmedString()
    }

    private func n(_ value: Double) -> String { Self.number(value) }

    /// How far the dot is from each side it touches: the dot distance for a
    /// corner, the search distance (how far it reaches) for a center.
    private var sideDistance: Double {
        flow.isCenter ? settings.searchDistance : settings.startInset
    }

    private func sideName(_ side: ProbeEdge) -> String {
        "\(side.rawValue) \(flow.isInside ? "wall" : "side")"
    }

    /// Where a pass of a center began: the tip's start, or the center the
    /// pass before found.
    private static func originKey(pass: Int) -> String {
        pass == 0 ? ProbeKey.start : "center-\(pass)"
    }

    /// Back to where a pass began, in machine coordinates (X and Y only).
    private func returnToOrigin(_ key: String, _ contacts: ProbeContacts) -> [String] {
        guard let origin = contacts[key] else { return ["; back to where the pass began"] }
        return ["G90", "G53 G0 X\(n(origin.x)) Y\(n(origin.y))", "G91"]
    }

    // MARK: Start and end

    private var prepare: ProbeStepPlan {
        ProbeStepPlan("Prepare",
                      measure: ProbeKey.start,
                      fixed: ["G21", "G92.1", settings.workCoordinateSystemName, "G91"])
    }

    private var finish: ProbeStepPlan {
        var lines = ["G90"]
        if settings.usesParkPosition {
            lines.append("G53 G0 X\(n(settings.parkX)) Y\(n(settings.parkY))")
        }
        return ProbeStepPlan(settings.usesParkPosition ? "Finish and park" : "Finish", fixed: lines)
    }

    // MARK: Touching

    /// Fast touch, back off, slow touch (or one touch if two-pass is off).
    /// Ends at the contact point.
    private func touchLines(_ axis: String, _ direction: Int, distance: Double) -> [String] {
        let sign = Double(direction)
        var lines = ["\(Self.probe) \(axis)\(n(sign * distance)) F\(n(settings.searchFeed))"]
        if settings.usesTwoPass {
            lines.append("G0 \(axis)\(n(-sign * settings.retractDistance))")
            lines.append("\(Self.probe) \(axis)\(n(sign * (settings.retractDistance + 1))) F\(n(settings.measureFeed))")
        }
        return lines
    }

    // MARK: Z

    /// Touch down on whatever is under the tip.
    private func topSteps(title: String) -> [ProbeStepPlan] {
        var lines = touchLines("Z", -1, distance: settings.searchDistance)
        if flow.setsZ(settings: settings) { lines.append(zeroLine) }
        lines.append("G0 Z\(n(settings.safeZ))")

        return [ProbeStepPlan(title,
                              measure: ProbeKey.zTop,
                              recovery: raiseLines,
                              check: Self.movedBeforeTouching,
                              fixed: lines)]
    }

    /// The line that makes the touched surface Z0.
    private var zeroLine: String {
        settings.zOffset == 0
            ? zeroZCommand
            : "G10 L20 P\(settings.workCoordinateSystem) Z\(n(settings.zOffset))"
    }

    /// A probe that did not move before it "touched" is already triggered.
    private static func movedBeforeTouching(_ contacts: ProbeContacts) -> String? {
        guard let start = contacts[ProbeKey.start], let top = contacts[ProbeKey.zTop] else { return nil }
        if start.z - top.z < 0.05 {
            return "The probe did not move before it touched. It may already be triggered: check the probe and its cable or battery."
        }
        return nil
    }

    // MARK: Pocket floor

    /// How far above the floor the walls are touched.
    private var wallHeight: Double { flow.wallHeight(settings: settings) }

    /// Touch the floor of a pocket, only to know the height the walls are
    /// touched at (the probe stays just above the floor).
    private func floorSteps() -> [ProbeStepPlan] {
        // The tip starts above the stock, so the floor is further than a plain touch.
        var lines = touchLines("Z", -1, distance: settings.searchDistance + settings.safeZ)
        lines.append("G0 Z\(n(wallHeight))")
        return [ProbeStepPlan("Touch the floor of the pocket",
                              measure: ProbeKey.zTop,
                              recovery: raiseLines,
                              check: Self.movedBeforeTouching,
                              fixed: lines)]
    }

    /// Back up to the height the cycle started at, which is above the stock.
    private var leavePocket: ProbeStepPlan {
        ProbeStepPlan("Raise out of the pocket") { contacts in
            guard let start = contacts[ProbeKey.start] else { return ["; raise to the height the cycle started at"] }
            return ["G90", "G53 G0 Z\(n(start.z))", "G91"]
        }
    }

    /// Straight up by the safe height, to get away from the stock.
    private var raiseLines: [String] {
        ["G91", "G0 Z\(n(settings.safeZ))", "G90"]
    }

    // MARK: Sides

    /// Move outside a side, lower beside the boss, touch it, come back.
    /// `distance` is how far the dot is from that side. A corner comes back
    /// by that distance; a center (`origin` set) comes back to where its pass
    /// began, because the distance is only a reach.
    private func sideSteps(axis: ProbeAxis, direction: Int, distance: Double,
                           depth: Double, pass: Int, name: String, origin: String?) -> [ProbeStepPlan] {
        let letter = axis.letter
        let sign = Double(direction)
        let outside = -sign * (distance + settings.outsideClearance)
        let loweredKey = ProbeKey.lowered(axis, direction, pass: pass)
        let travel = max(settings.searchDistance, distance + settings.outsideClearance)

        return [
            ProbeStepPlan("Move outside the \(name) and lower",
                          measure: loweredKey,
                          recovery: raiseLines,
                          check: loweredCheck(key: loweredKey, depth: depth),
                          fixed: ["G0 \(letter)\(n(outside))", lowerLine(depth: depth)]),

            ProbeStepPlan("Touch the \(name)",
                          measure: ProbeKey.side(axis, direction, pass: pass),
                          recovery: raiseLines,
                          fixed: touchLines(letter, direction, distance: travel)),

            ProbeStepPlan("Back above the boss") { contacts in
                var lines = ["G0 Z\(n(depth + settings.safeZ))"]
                if let origin {
                    lines += returnToOrigin(origin, contacts)
                } else {
                    lines.append("G0 \(letter)\(n(sign * (distance + radius)))")
                }
                return lines
            },
        ]
    }

    /// Lowers from the safe height to `depth` below the top without an error
    /// if nothing is touched. Touching something is what the check looks for.
    private func lowerLine(depth: Double) -> String {
        "\(Self.probeQuiet) Z\(n(-(settings.safeZ + depth))) F\(n(settings.searchFeed))"
    }

    private func loweredCheck(key: String, depth: Double) -> (ProbeContacts) -> String? {
        { contacts in
            guard let top = contacts[ProbeKey.zTop], let lowered = contacts[key] else { return nil }
            // It should have gone all the way down. Stopping higher means it
            // touched something on the way.
            if lowered.z > top.z - depth + 0.3 {
                return "The probe touched something while lowering beside the boss. The start position may have been off the boss, or the boss is wider than the search distance: raise Z, jog above the dot and try again."
            }
            return nil
        }
    }

    /// The chosen sides of the boss, one after another, each from outside.
    private func stockSideSteps(pass: Int, origin: String?) -> [ProbeStepPlan] {
        flow.sides.flatMap { side -> [ProbeStepPlan] in
            let (axis, direction) = flow.probeDirection(for: side)
            return sideSteps(axis: axis, direction: direction, distance: sideDistance,
                             depth: settings.edgeDepth, pass: pass,
                             name: sideName(side), origin: origin)
        }
    }

    /// The chosen walls of a pocket, one after another, each from inside: touch
    /// the wall, then come back to where the probe started.
    private func pocketWallSteps(pass: Int, origin: String?) -> [ProbeStepPlan] {
        let travel = max(settings.searchDistance, sideDistance + settings.outsideClearance)
        return flow.sides.flatMap { side -> [ProbeStepPlan] in
            let (axis, direction) = flow.probeDirection(for: side)
            let sign = Double(direction)
            return [
                ProbeStepPlan("Touch the \(sideName(side))",
                              measure: ProbeKey.side(axis, direction, pass: pass),
                              recovery: raiseLines,
                              fixed: touchLines(axis.letter, direction, distance: travel)),
                ProbeStepPlan("Back to the start") { contacts in
                    if let origin { return returnToOrigin(origin, contacts) }
                    return ["G0 \(axis.letter)\(n(-sign * (sideDistance - radius)))"]
                },
            ]
        }
    }

    // MARK: Centers

    /// A move, in machine coordinates, to the middle of the contacts of `pass`.
    /// With `key`, the position it ends at is kept as the start of a next pass.
    private func moveToCenterStep(pass: Int, title: String, key: String? = nil) -> ProbeStepPlan {
        ProbeStepPlan(title, measure: key) { contacts in
            guard let left = contacts[ProbeKey.side(.x, 1, pass: pass)],
                  let right = contacts[ProbeKey.side(.x, -1, pass: pass)],
                  let bottom = contacts[ProbeKey.side(.y, 1, pass: pass)],
                  let top = contacts[ProbeKey.side(.y, -1, pass: pass)]
            else { return ["; move to the middle of the four touches"] }
            return ["G90",
                    "G53 G0 X\(n((left.x + right.x) / 2)) Y\(n((bottom.y + top.y) / 2))",
                    "G91"]
        }
    }

    /// Four sides, then the middle. The middle of two opposite touches is the
    /// center whatever the shape, so this finds a round boss as well as a
    /// square one. A second pass starts from the center found, which makes a
    /// round feature's size accurate too.
    private func centerSteps() -> [ProbeStepPlan] {
        let passes = settings.refinesCircle ? 2 : 1
        var steps: [ProbeStepPlan] = []

        for pass in 0..<passes {
            if pass > 0 {
                steps.append(moveToCenterStep(pass: pass - 1,
                                              title: "Move to the center found so far",
                                              key: Self.originKey(pass: pass)))
            }
            let origin = Self.originKey(pass: pass)
            steps += flow.isInside
                ? pocketWallSteps(pass: pass, origin: origin)
                : stockSideSteps(pass: pass, origin: origin)
        }
        steps.append(moveToCenterStep(pass: passes - 1, title: "Move to the center"))
        return steps
    }
}
