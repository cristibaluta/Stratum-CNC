//
//  ProbeResult.swift
//  Stratum CNC
//
//  Turns the machine positions a probing cycle read into what the person
//  cares about: where the edges are, the new work origin, the measured size,
//  and anything that looks wrong. Pure: no machine, no UI.
//
//  The one rule behind every edge. When the ball touches, the machine stops
//  with the BALL CENTER one radius `r` short of the surface, on the side the
//  probe came from. So, for a touch while moving in direction `d` (+1 toward
//  +X/+Y, −1 toward −X/−Y):
//
//      surface = contact + d · r
//
//  This holds for a side of a block, a round boss touched from outside, and
//  a hole touched from inside. In a center, the two radii cancel out.
//
//  Everything here is in machine coordinates (X right, Y toward the back).
//

import Foundation

struct ProbeResult: Equatable {

    struct Row: Equatable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// What was measured, for the table.
    private(set) var rows: [Row] = []
    /// Where the new work origin is, in machine coordinates. A cycle that
    /// only finds one axis leaves the other nil.
    private(set) var originX: Double?
    private(set) var originY: Double?
    /// Machine Z of the stock's top, if it was touched. Informational: Z0 was
    /// written during the cycle.
    private(set) var surfaceZ: Double?
    /// Things that look wrong, in plain words.
    private(set) var warnings: [String] = []

    /// How far a measured size may differ from the stock's before it is
    /// reported (mm).
    static let sizeTolerance = 1.0

    var hasOrigin: Bool { originX != nil || originY != nil }

    // MARK: Compute

    init(flow: ProbeFlow,
         settings: ProbeSettings,
         contacts: ProbeContacts,
         bedMin: SIMD2<Double>? = nil,
         bedMax: SIMD2<Double>? = nil) {

        let radius = settings.ballRadius

        if let top = contacts[ProbeKey.zTop] {
            surfaceZ = top.z
            rows.append(Row(label: flow.probesPocket ? "Floor of the pocket (machine Z)" : "Top of the stock (machine Z)",
                            value: Self.format(top.z)))
        }

        let subject = flow.isInside ? (flow.hasHole ? "hole" : "pocket") : "stock"
        let sideWord = flow.isInside ? "wall" : "side"

        switch flow.kind {
            case .zSurface:
                break

            case .point:
                if flow.effectivePoint.isCenter {
                    if flow.shape == .rectangle {
                        rectangleCenter(flow: flow, contacts: contacts, radius: radius, subject: subject)
                    } else {
                        circleCenter(flow: flow, contacts: contacts, radius: radius, subject: subject)
                    }
                } else {
                    for side in flow.sides {
                        if let value = Self.surface(flow, side, contacts, pass: 0, radius: radius) {
                            assign(side.axis, value)
                            rows.append(Row(label: "\(side.title) \(sideWord) (machine \(side.axis.letter))",
                                            value: Self.format(value)))
                        }
                    }
                }
        }

        if let bedMin, let bedMax {
            checkBed(bedMin: bedMin, bedMax: bedMax)
        }
    }

    private mutating func assign(_ axis: ProbeAxis, _ value: Double) {
        switch axis {
            case .x: originX = value
            case .y: originY = value
        }
    }

    private mutating func rectangleCenter(flow: ProbeFlow, contacts: ProbeContacts, radius: Double, subject: String) {
        guard let left = Self.surface(flow, .left, contacts, pass: 0, radius: radius),
              let right = Self.surface(flow, .right, contacts, pass: 0, radius: radius),
              let bottom = Self.surface(flow, .bottom, contacts, pass: 0, radius: radius),
              let top = Self.surface(flow, .top, contacts, pass: 0, radius: radius)
        else { return }

        originX = (left + right) / 2
        originY = (bottom + top) / 2

        let width = right - left
        let height = top - bottom
        rows.append(Row(label: "Width", value: Self.format(width, unit: "mm")))
        rows.append(Row(label: "Height", value: Self.format(height, unit: "mm")))
        rows.append(Row(label: "Center (machine)", value: "X \(Self.format(originX ?? 0))   Y \(Self.format(originY ?? 0))"))

        let expected = flow.featureSize
        compare(width, with: expected.width, name: "width", subject: subject)
        compare(height, with: expected.height, name: "height", subject: subject)
    }

    private mutating func circleCenter(flow: ProbeFlow, contacts: ProbeContacts, radius: Double, subject: String) {
        // The refined pass, if it ran, otherwise the first.
        for pass in [1, 0] {
            guard let left = Self.surface(flow, .left, contacts, pass: pass, radius: radius),
                  let right = Self.surface(flow, .right, contacts, pass: pass, radius: radius),
                  let bottom = Self.surface(flow, .bottom, contacts, pass: pass, radius: radius),
                  let top = Self.surface(flow, .top, contacts, pass: pass, radius: radius)
            else { continue }

            // The middle of a chord is the center whatever row the chord is on
            // (the perpendicular bisector of any chord passes through the
            // center). The chord is only the full diameter when it passes
            // through the center, which is what the second pass is for.
            let diameterX = abs(right - left)
            let diameterY = abs(top - bottom)
            originX = (left + right) / 2
            originY = (bottom + top) / 2

            rows.append(Row(label: "Diameter (X)", value: Self.format(diameterX, unit: "mm")))
            rows.append(Row(label: "Diameter (Y)", value: Self.format(diameterY, unit: "mm")))
            rows.append(Row(label: "Center (machine)", value: "X \(Self.format(originX ?? 0))   Y \(Self.format(originY ?? 0))"))

            let nominal = flow.featureSize.width
            compare(diameterX, with: nominal, name: "diameter in X", subject: subject)
            compare(diameterY, with: nominal, name: "diameter in Y", subject: subject)
            return
        }
    }

    private mutating func compare(_ measured: Double, with expected: Double, name: String, subject: String) {
        guard abs(measured - expected) > Self.sizeTolerance else { return }
        warnings.append("The measured \(name) is \(Self.format(measured, unit: "mm")), but the \(subject) is \(Self.format(expected, unit: "mm")). The wrong \(subject == "stock" ? "stock may be selected" : "size may be entered"), or a wrong surface was touched.")
    }

    /// The origin has to be on the bed.
    private mutating func checkBed(bedMin: SIMD2<Double>, bedMax: SIMD2<Double>) {
        if let x = originX, x < bedMin.x || x > bedMax.x {
            warnings.append("The X origin (\(Self.format(x))) is outside the bed.")
        }
        if let y = originY, y < bedMin.y || y > bedMax.y {
            warnings.append("The Y origin (\(Self.format(y))) is outside the bed.")
        }
    }

    // MARK: Edges

    /// The surface of `side` of the feature, from the touch that found it.
    static func surface(_ flow: ProbeFlow, _ side: ProbeEdge, _ contacts: ProbeContacts,
                        pass: Int, radius: Double) -> Double? {
        let (axis, direction) = flow.probeDirection(for: side)
        return edge(contacts, axis, direction, pass: pass, radius: radius)
    }

    /// The surface found by a touch: contact + direction · radius.
    static func edge(_ contacts: ProbeContacts, _ axis: ProbeAxis, _ direction: Int,
                     pass: Int, radius: Double) -> Double? {
        guard let contact = contacts[ProbeKey.side(axis, direction, pass: pass)] else { return nil }
        let value = axis == .x ? contact.x : contact.y
        return value + Double(direction) * radius
    }

    // MARK: Writing the origin

    /// `G10 L2 P<n> X.. Y..`: "the origin is at this machine position".
    /// Absolute, so it doesn't depend on where the tool is. Only the axes that
    /// were measured are written.
    func originCommand(workCoordinateSystem: Int) -> String? {
        guard hasOrigin else { return nil }
        var command = "G10 L2 P\(workCoordinateSystem)"
        if let originX { command += " X\(ProbeCycleBuilder.number(originX))" }
        if let originY { command += " Y\(ProbeCycleBuilder.number(originY))" }
        return command
    }

    /// The canvas job offset that puts the work origin here:
    /// `workOrigin = anchor + xyOffset`, so `xyOffset = origin − anchor`.
    /// An axis that wasn't measured keeps `current`.
    func xyOffset(anchor: SIMD2<Double>, current: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2((originX ?? (anchor.x + current.x)) - anchor.x,
              (originY ?? (anchor.y + current.y)) - anchor.y)
    }

    /// Whether the lines the app sends at the start of a run (`G10 L2 …`)
    /// carry the origin measured here. If not, starting a run would move the
    /// origin somewhere else.
    func isCarried(by lines: [String]) -> Bool {
        guard hasOrigin else { return true }
        let origin = lines.filter { $0.uppercased().contains("G10") }
        return origin.contains { line in
            let x = Self.number(after: "X", in: line)
            let y = Self.number(after: "Y", in: line)
            let xMatches = originX.map { expected in x.map { abs($0 - expected) < 0.01 } ?? false } ?? true
            let yMatches = originY.map { expected in y.map { abs($0 - expected) < 0.01 } ?? false } ?? true
            return xMatches && yMatches
        }
    }

    /// The number right after a letter, as in "X-179.5".
    private static func number(after letter: String, in line: String) -> Double? {
        guard let range = line.range(of: "\(letter)(-?[0-9]+(\\.[0-9]+)?)", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return Double(line[range].dropFirst())
    }

    // MARK: Format

    static func format(_ value: Double, unit: String? = nil) -> String {
        let text = String(format: "%.3f", value)
        return unit.map { "\(text) \($0)" } ?? text
    }
}

/// What Apply changed, so it can be undone.
struct ProbeAppliedOrigin: Equatable {
    var workCoordinateSystem: Int
    var changedX: Bool
    var changedY: Bool
    /// The canvas job offset before Apply.
    var previousXYOffset: SIMD2<Float>
    /// The work origin on the machine before the cycle ran (machine position
    /// minus work position, read just before). Nil if it wasn't known.
    var previousMachineOrigin: SIMD2<Double>?

    /// Puts the previous origin back on the machine, for the axes Apply changed.
    var revertCommand: String? {
        guard let previous = previousMachineOrigin, changedX || changedY else { return nil }
        var command = "G10 L2 P\(workCoordinateSystem)"
        if changedX { command += " X\(ProbeCycleBuilder.number(previous.x))" }
        if changedY { command += " Y\(ProbeCycleBuilder.number(previous.y))" }
        return command
    }
}
