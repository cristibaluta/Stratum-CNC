//
//  ProbeCycleBuilder.swift
//  Stratum CNC
//
//  Turns "what to probe" + the settings + the stock into the list of steps a
//  cycle runs. Pure: no machine, no UI, so every sign and distance is tested.
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
        if flow.probesInsideHole,
           case let .disk(_, innerDiameter, _) = flow.geometry,
           innerDiameter / 2 <= settings.ballRadius + 0.5 {
            result.append("The hole is too small for the probe ball.")
        }
        if flow.probesZFirst, flow.thickness < 2 {
            result.append("The stock is too thin to touch its sides.")
        }
        return result
    }

    // MARK: Build

    func build() -> [ProbeStepPlan] {
        var steps = [prepare]

        switch flow.kind {
            case .zSurface:
                steps += topSteps(ringOffset: nil)

            case .edge:
                steps += topSteps(ringOffset: nil)
                let (axis, direction) = edgeSide
                steps += sideSteps(axis: axis, direction: direction, distance: edgeDistance(axis, direction),
                                   depth: depth(for: axis), pass: 0, name: sideName(axis, direction))

            case .corner:
                steps += topSteps(ringOffset: nil)
                let xDirection = flow.corner.isLeft ? 1 : -1
                let yDirection = flow.corner.isBottom ? 1 : -1
                steps += sideSteps(axis: .x, direction: xDirection, distance: edgeDistance(.x, xDirection),
                                   depth: depth(for: .x), pass: 0, name: sideName(.x, xDirection))
                steps += sideSteps(axis: .y, direction: yDirection, distance: edgeDistance(.y, yDirection),
                                   depth: depth(for: .y), pass: 0, name: sideName(.y, yDirection))

            case .center:
                if flow.shape == .rectangle {
                    steps += topSteps(ringOffset: nil)
                    steps += rectangleCenterSteps()
                } else {
                    steps += topSteps(ringOffset: flow.probesInsideHole ? ringOffset : nil)
                    steps += circleCenterSteps()
                }
        }

        steps.append(finish)
        return steps
    }

    // MARK: Numbers

    private var radius: Double { settings.ballRadius }
    private var size: (width: Double, height: Double) { ProbeFlow.footprint(of: flow.geometry) }
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
        if case .cylindrical = flow.geometry, axis == .y {
            return flow.thickness / 2
        }
        return settings.edgeDepth(forStockThickness: flow.thickness)
    }

    /// The side the single-edge cycle touches.
    private var edgeSide: (ProbeAxis, Int) {
        switch flow.edge {
            case .left: (.x, 1)
            case .right: (.x, -1)
            case .bottom: (.y, 1)
            case .top: (.y, -1)
        }
    }

    /// Distance from the dot to the side the probe touches when moving in
    /// `direction` (+1 touches the left or bottom side, −1 the right or top).
    private func edgeDistance(_ axis: ProbeAxis, _ direction: Int) -> Double {
        switch (axis, direction > 0) {
            case (.x, true): dot.x
            case (.x, false): size.width - dot.x
            case (.y, true): dot.y
            case (.y, false): size.height - dot.y
        }
    }

    private func sideName(_ axis: ProbeAxis, _ direction: Int) -> String {
        switch (axis, direction > 0) {
            case (.x, true): "left side"
            case (.x, false): "right side"
            case (.y, true): "bottom side"
            case (.y, false): "top side"
        }
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
        if flow.kind == .zSurface || settings.setsZ {
            lines.append(settings.zOffset == 0
                ? zeroZCommand
                : "G10 L20 P\(settings.workCoordinateSystem) Z\(n(settings.zOffset))")
        }
        lines.append("G0 Z\(n(settings.safeZ))")

        steps.append(ProbeStepPlan("Touch the top",
                                   measure: ProbeKey.zTop,
                                   recovery: raiseLines,
                                   check: { contacts in
            guard let start = contacts[ProbeKey.start], let top = contacts[ProbeKey.zTop] else { return nil }
            if start.z - top.z < 0.05 {
                return "The probe did not move before it touched. It may already be triggered: check the probe and its cable or battery."
            }
            return nil
        }, fixed: lines))

        if ring != nil {
            steps.append(ProbeStepPlan("Back over the hole", fixed: ["G0 X\(n(-(ring ?? 0)))"]))
        }
        return steps
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

    // MARK: Rectangle center

    private func rectangleCenterSteps() -> [ProbeStepPlan] {
        var steps: [ProbeStepPlan] = []
        for (axis, direction) in [(ProbeAxis.x, 1), (.x, -1), (.y, 1), (.y, -1)] {
            steps += sideSteps(axis: axis, direction: direction, distance: edgeDistance(axis, direction),
                               depth: depth(for: axis), pass: 0, name: sideName(axis, direction))
        }
        steps.append(moveToCenterStep(pass: 0, title: "Move to the center"))
        return steps
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
            steps += flow.probesInsideHole ? holeSteps(pass: pass) : bossSteps(pass: pass)
        }
        steps.append(moveToCenterStep(pass: passes - 1, title: "Move to the center"))
        return steps
    }

    private var circleDirections: [(ProbeAxis, Int)] { [(.x, 1), (.x, -1), (.y, 1), (.y, -1)] }

    /// Round stock: touched from outside, one side after another.
    private func bossSteps(pass: Int) -> [ProbeStepPlan] {
        let outer = size.width / 2
        let depth = settings.edgeDepth(forStockThickness: flow.thickness)
        return circleDirections.flatMap { axis, direction in
            sideSteps(axis: axis, direction: direction, distance: outer, depth: depth,
                      pass: pass, name: "\(sideName(axis, direction)) of the stock")
        }
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

        for (axis, direction) in circleDirections {
            let sign = Double(direction)
            steps.append(ProbeStepPlan("Touch the \(sideName(axis, direction).replacingOccurrences(of: "side", with: "wall"))",
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
