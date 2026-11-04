//
//  ProbeCycleBuilder.swift
//  Stratum CNC
//
//  Turns "what to probe" + the settings + the stock into the list of steps a
//  cycle runs. Pure: no machine, no UI, so every sign and distance is tested.
//
//  Two ways in, depending on the surface:
//    outside (stock): touch the top, then each side from outside, lowering
//      beside the stock first.
//    inside (pocket): touch the floor to know the height, rise a little, then
//      touch each wall from inside, moving out. A disk's through-hole has no
//      floor, so there the top is touched on the ring around it instead.
//
//  The cycle starts with the probe tip above the dot (see `ProbeFlow.targetPoint`)
//  and moves RELATIVE (G91) from there, so it does not depend on the work
//  offset. Positions that matter are read back in machine coordinates and the
//  origin is written afterwards from them.
//
//  Moves, in short, for a side:
//    1. at safe height, move outside the side, then lower beside the stock
//       (with a probe move that must NOT touch anything: if it does, the
//       start position was wrong and the cycle stops)
//    2. touch the side (fast, back off, slow)
//    3. raise and come back to the dot
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
        let size = flow.featureSize

        if flow.kind == .point, flow.isInside,
           min(size.width, size.height) / 2 <= settings.ballRadius + 0.5 {
            result.append("The \(flow.hasHole ? "hole" : "pocket") is too small for the probe ball.")
        }
        if flow.probesPocket {
            let stock = ProbeFlow.footprint(of: flow.geometry)
            if size.width > stock.width || size.height > stock.height {
                result.append("The pocket is bigger than the stock.")
            }
            if flow.kind == .point, flow.pocketDepth < 2 {
                result.append("The pocket is too shallow to touch its walls.")
            }
        } else if flow.probesZFirst, flow.thickness < 2 {
            result.append("The stock is too thin to touch its sides.")
        }
        return result
    }

    // MARK: Build

    func build() -> [ProbeStepPlan] {
        var steps = [prepare]

        switch flow.kind {
            case .zSurface:
                steps += flow.probesPocket ? floorSteps() : topSteps(ringOffset: nil)

            case .point:
                let isCenter = flow.effectivePoint.isCenter
                let isRound = flow.shape == .circle

                if flow.probesInsideHole {
                    steps += topSteps(ringOffset: ringOffset)
                    steps += circleCenterSteps()
                } else if flow.probesPocket {
                    steps += floorSteps()
                    steps += isCenter && isRound ? circleCenterSteps() : pocketWallSteps(pass: 0)
                    if isCenter && !isRound { steps.append(moveToCenterStep(pass: 0, title: "Move to the center")) }
                    steps.append(raiseOutOfPocket)
                } else {
                    steps += topSteps(ringOffset: nil)
                    if isCenter && isRound {
                        steps += circleCenterSteps()
                    } else {
                        steps += stockSideSteps(pass: 0)
                        if isCenter { steps.append(moveToCenterStep(pass: 0, title: "Move to the center")) }
                    }
                }
        }

        steps.append(finish)
        return steps
    }

    // MARK: Numbers

    private var radius: Double { settings.ballRadius }
    private var size: (width: Double, height: Double) { flow.featureSize }
    private var dot: (x: Double, y: Double) { flow.targetPoint(inset: settings.startInset) }

    /// 10 → "10", 1.5 → "1.5", −0.0004 → "0".
    static func number(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    private func n(_ value: Double) -> String { Self.number(value) }

    /// How far below the top a side is touched. A cylinder lying on the bed is
    /// widest at its middle, so its long sides are touched at half its height.
    private func depth(for axis: ProbeAxis) -> Double {
        if case .cylindrical = flow.geometry, axis == .y, !flow.isRoundBoss {
            return flow.thickness / 2
        }
        return settings.edgeDepth(forStockThickness: flow.thickness)
    }

    /// Distance from the dot to `side` of the feature.
    private func distance(to side: ProbeEdge) -> Double {
        switch side {
            case .left: dot.x
            case .right: size.width - dot.x
            case .bottom: dot.y
            case .top: size.height - dot.y
        }
    }

    private func sideName(_ side: ProbeEdge) -> String {
        "\(side.rawValue) \(flow.isInside ? "wall" : "side")"
    }

    /// Between the ring around a hole and its center, along X.
    private var ringOffset: Double {
        if case let .disk(outerDiameter, innerDiameter, _) = flow.geometry {
            return (outerDiameter + innerDiameter) / 4
        }
        return 0
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

    private func topSteps(ringOffset ring: Double?) -> [ProbeStepPlan] {
        var steps: [ProbeStepPlan] = []

        if let ring {
            steps.append(ProbeStepPlan("Move over the ring around the hole", fixed: ["G0 X\(n(ring))"]))
        }

        var lines = touchLines("Z", -1, distance: settings.searchDistance)
        if flow.setsZ(settings: settings) { lines.append(zeroLine) }
        lines.append("G0 Z\(n(settings.safeZ))")

        steps.append(ProbeStepPlan("Touch the top",
                                   measure: ProbeKey.zTop,
                                   recovery: raiseLines,
                                   check: Self.movedBeforeTouching,
                                   fixed: lines))

        if ring != nil {
            steps.append(ProbeStepPlan("Back over the hole", fixed: ["G0 X\(n(-(ring ?? 0)))"]))
        }
        return steps
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

    /// Touch the floor of a pocket. For a Z surface it becomes Z0 and the
    /// probe goes back up; for a point it only gives the height the walls are
    /// touched at (the probe stays just above the floor).
    private func floorSteps() -> [ProbeStepPlan] {
        // The tip starts above the stock, so the floor can be a whole pocket depth away.
        var lines = touchLines("Z", -1, distance: max(settings.searchDistance, flow.pocketDepth + settings.safeZ))
        if flow.kind == .zSurface {
            lines.append(zeroLine)
            lines.append("G0 Z\(n(flow.pocketDepth + settings.safeZ))")
        } else {
            lines.append("G0 Z\(n(wallHeight))")
        }
        return [ProbeStepPlan("Touch the floor of the pocket",
                              measure: ProbeKey.zTop,
                              recovery: raiseLines,
                              check: Self.movedBeforeTouching,
                              fixed: lines)]
    }

    private var raiseOutOfPocket: ProbeStepPlan {
        ProbeStepPlan("Raise out of the pocket",
                      fixed: ["G0 Z\(n(flow.pocketDepth - wallHeight + settings.safeZ))"])
    }

    /// Straight up by the safe height, to get away from the stock.
    private var raiseLines: [String] {
        ["G91", "G0 Z\(n(settings.safeZ))", "G90"]
    }

    // MARK: Sides

    /// Move outside a side, lower beside the stock, touch it, come back.
    /// `distance` is how far the dot is from that side (a circle's radius for
    /// a round stock).
    private func sideSteps(axis: ProbeAxis, direction: Int, distance: Double,
                           depth: Double, pass: Int, name: String) -> [ProbeStepPlan] {
        let letter = axis.letter
        let sign = Double(direction)
        let outside = -sign * (distance + settings.outsideClearance)
        let loweredKey = ProbeKey.lowered(axis, direction, pass: pass)

        return [
            ProbeStepPlan("Move outside the \(name) and lower",
                          measure: loweredKey,
                          recovery: raiseLines,
                          check: loweredCheck(key: loweredKey, depth: depth),
                          fixed: ["G0 \(letter)\(n(outside))", lowerLine(depth: depth)]),

            ProbeStepPlan("Touch the \(name)",
                          measure: ProbeKey.side(axis, direction, pass: pass),
                          recovery: raiseLines,
                          fixed: touchLines(letter, direction, distance: settings.searchDistance)),

            ProbeStepPlan("Back above the stock",
                          fixed: ["G0 Z\(n(depth + settings.safeZ))",
                                  "G0 \(letter)\(n(sign * (distance + radius)))"]),
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
                return "The probe touched something while lowering beside the stock. The start position may have been over the stock: raise Z, jog above the dot and try again."
            }
            return nil
        }
    }

    // MARK: Sides of a rectangle

    /// The chosen sides of the stock, one after another, each from outside.
    private func stockSideSteps(pass: Int) -> [ProbeStepPlan] {
        flow.sides.flatMap { side -> [ProbeStepPlan] in
            let (axis, direction) = flow.probeDirection(for: side)
            return sideSteps(axis: axis, direction: direction, distance: distance(to: side),
                             depth: depth(for: axis), pass: pass, name: sideName(side))
        }
    }

    /// The chosen walls of a pocket, one after another, each from inside: touch
    /// the wall, then come back to where the probe started.
    private func pocketWallSteps(pass: Int) -> [ProbeStepPlan] {
        let travel = max(settings.searchDistance,
                         flow.sides.map { distance(to: $0) }.max().map { $0 + settings.outsideClearance } ?? 0)
        return flow.sides.flatMap { side -> [ProbeStepPlan] in
            let (axis, direction) = flow.probeDirection(for: side)
            let sign = Double(direction)
            return [
                ProbeStepPlan("Touch the \(sideName(side))",
                              measure: ProbeKey.side(axis, direction, pass: pass),
                              recovery: raiseLines,
                              fixed: touchLines(axis.letter, direction, distance: travel)),
                ProbeStepPlan("Back to the start",
                              fixed: ["G0 \(axis.letter)\(n(-sign * (distance(to: side) - radius)))"]),
            ]
        }
    }

    /// A move, in machine coordinates, to the middle of the contacts of `pass`.
    private func moveToCenterStep(pass: Int, title: String) -> ProbeStepPlan {
        ProbeStepPlan(title) { contacts in
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

    // MARK: Circle center

    private func circleCenterSteps() -> [ProbeStepPlan] {
        let passes = settings.refinesCircle ? 2 : 1
        var steps: [ProbeStepPlan] = []

        for pass in 0..<passes {
            if pass > 0 {
                steps.append(moveToCenterStep(pass: pass - 1, title: "Move to the center found so far"))
            }
            if flow.probesInsideHole {
                steps += holeSteps(pass: pass)
            } else if flow.probesPocket {
                steps += pocketWallSteps(pass: pass)
            } else {
                steps += stockSideSteps(pass: pass)
            }
        }
        steps.append(moveToCenterStep(pass: passes - 1, title: "Move to the center"))
        return steps
    }

    /// A hole: lowered into once, touched from inside in four directions.
    private func holeSteps(pass: Int) -> [ProbeStepPlan] {
        guard case let .disk(_, innerDiameter, _) = flow.geometry else { return [] }
        let holeRadius = innerDiameter / 2
        let depth = settings.edgeDepth(forStockThickness: flow.thickness)
        let travel = max(settings.searchDistance, holeRadius + settings.outsideClearance)
        let firstKey = ProbeKey.lowered(.x, 1, pass: pass)

        var steps = [
            ProbeStepPlan("Lower into the hole",
                          measure: firstKey,
                          recovery: raiseLines,
                          check: loweredCheck(key: firstKey, depth: depth),
                          fixed: [lowerLine(depth: depth)]),
        ]

        for side in flow.sides {
            let (axis, direction) = flow.probeDirection(for: side)
            let sign = Double(direction)
            steps.append(ProbeStepPlan("Touch the \(sideName(side))",
                                       measure: ProbeKey.side(axis, direction, pass: pass),
                                       recovery: raiseLines,
                                       fixed: touchLines(axis.letter, direction, distance: travel)))
            steps.append(ProbeStepPlan("Back to the middle of the hole",
                                       fixed: ["G0 \(axis.letter)\(n(-sign * (holeRadius - radius)))"]))
        }

        steps.append(ProbeStepPlan("Raise out of the hole",
                                   fixed: ["G0 Z\(n(depth + settings.safeZ))"]))
        return steps
    }
}
