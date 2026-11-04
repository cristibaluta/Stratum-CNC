//
//  ProbeFlow.swift
//  Stratum CNC
//
//  The state and rules of the 3D probing dialog: which step it is on, what is
//  being probed, and where the probe should be jogged to. Pure state;
//  `ProbeSheet` presents it. Same split as `BitChangeFlow` / `BitChangeSheet`.
//
//  Feature coordinates used here: origin at the bottom-left corner of the thing
//  being probed (the stock, or the pocket) seen from above, X to the right,
//  Y up, millimeters.
//

import Foundation

struct ProbeFlow: Equatable {

    enum Step: Int, CaseIterable, Equatable {
        case what
        case position
        case probe
        case result

        var title: String {
            switch self {
                case .what: "What"
                case .position: "Position"
                case .probe: "Probe"
                case .result: "Result"
            }
        }
    }

    private(set) var step: Step = .what

    let geometry: StockGeometry

    var kind: ProbeKind = .point
    var surface: ProbeSurface
    /// Which of the nine points is probed. Round features only have the center.
    var point: ProbePoint = .bottomLeft

    /// A pocket the person describes, because the stock does not know about
    /// it. Used when probing the inside of anything but a disk's hole.
    var pocketShape: ProbeShape = .rectangle
    var pocketWidth = 40.0
    var pocketHeight = 30.0
    var pocketDepth = 10.0

    /// A round boss or pin on a stock that is not itself round (a disk is
    /// already round). Probed from outside like round stock; its diameter is
    /// entered because the stock does not know about it.
    var outsideIsRound = false
    var bossDiameter = 30.0

    init(geometry: StockGeometry) {
        self.geometry = geometry
        surface = Self.defaultSurface(for: geometry)
        if Self.defaultShape(for: geometry) == .circle { point = .center }
    }

    // MARK: What is being probed

    /// The shape and size, seen from above, of the thing the probe touches:
    /// the stock when probing the outside, the pocket or hole when probing
    /// the inside.
    struct Feature: Equatable {
        var shape: ProbeShape
        var width: Double
        var height: Double
    }

    /// A disk with a hole can be probed from outside or from inside.
    var hasHole: Bool {
        if case let .disk(_, innerDiameter, _) = geometry { return innerDiameter > 0 }
        return false
    }

    var isDisk: Bool {
        if case .disk = geometry { return true }
        return false
    }

    /// The outside of a round boss sitting on a rectangular stock.
    var isRoundBoss: Bool { !isInside && outsideIsRound && !isDisk }

    /// True when the inside is probed. The Z surface of a disk with a hole is
    /// always the top of the stock (the ring), so it never counts as inside.
    var isInside: Bool { surface == .inside && !(kind == .zSurface && hasHole) }

    /// The inside of a disk's hole: its size is known, it goes all the way
    /// through, and Z is touched on the ring around it.
    var probesInsideHole: Bool { kind == .point && isInside && hasHole }

    /// The inside of a pocket the person described: it has a floor, and that
    /// is where Z is touched.
    var probesPocket: Bool { isInside && !hasHole }

    var feature: Feature {
        guard isInside else {
            if isRoundBoss { return Feature(shape: .circle, width: bossDiameter, height: bossDiameter) }
            let size = Self.footprint(of: geometry)
            return Feature(shape: Self.defaultShape(for: geometry), width: size.width, height: size.height)
        }
        if case let .disk(_, innerDiameter, _) = geometry, innerDiameter > 0 {
            return Feature(shape: .circle, width: innerDiameter, height: innerDiameter)
        }
        switch pocketShape {
            case .rectangle: return Feature(shape: .rectangle, width: pocketWidth, height: pocketHeight)
            case .circle: return Feature(shape: .circle, width: pocketWidth, height: pocketWidth)
        }
    }

    var shape: ProbeShape { feature.shape }

    /// Size of the feature seen from above.
    var featureSize: (width: Double, height: Double) { (feature.width, feature.height) }

    /// The point actually probed: a round feature only has its center.
    var effectivePoint: ProbePoint { shape == .circle ? .center : point }

    /// Whether the drawing offers the nine points to choose from.
    var choosesPoint: Bool { kind == .point && shape == .rectangle }

    // MARK: Defaults from the stock

    /// A cylinder lies on the bed, so from above it is a `length × diameter`
    /// rectangle; only a disk is round from above.
    static func defaultShape(for geometry: StockGeometry) -> ProbeShape {
        switch geometry {
            case .rectangular, .cylindrical: .rectangle
            case .disk: .circle
        }
    }

    /// A disk with a hole defaults to probing the hole.
    static func defaultSurface(for geometry: StockGeometry) -> ProbeSurface {
        if case let .disk(_, innerDiameter, _) = geometry, innerDiameter > 0 {
            return .inside
        }
        return .outside
    }

    /// Size of the stock seen from above.
    static func footprint(of geometry: StockGeometry) -> (width: Double, height: Double) {
        switch geometry {
            case let .rectangular(width, height, _): (width, height)
            case let .cylindrical(diameter, length): (length, diameter)
            case let .disk(outerDiameter, _, _): (outerDiameter, outerDiameter)
        }
    }

    /// How tall the stock is, used to keep side touches inside it.
    /// (`sortDepth`: the depth, or the diameter for a cylinder.)
    var thickness: Double { geometry.sortDepth }

    // MARK: Choosing

    var availableKinds: [ProbeKind] { ProbeKind.allCases }

    /// The sides the chosen point needs touched, in the order they are
    /// probed. A corner is two sides, a side midpoint one, the center four.
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
    /// From outside the probe moves toward the stock (+ to reach the left or
    /// bottom side); from inside it moves out toward the wall (the opposite).
    func probeDirection(for side: ProbeEdge) -> (axis: ProbeAxis, direction: Int) {
        let towardPositive = side == .left || side == .bottom
        return (side.axis, (!isInside) == towardPositive ? 1 : -1)
    }

    /// X and Y both need Z first: the sides are touched at a depth below the top.
    var probesZFirst: Bool { kind != .zSurface }

    /// Whether Z0 is written during the cycle. Inside a pocket the floor is
    /// touched to find the height, but Z0 is only set there when Z is the thing
    /// being probed: it is normally on the top of the stock, which is not
    /// touched.
    func setsZ(settings: ProbeSettings) -> Bool {
        if kind == .zSurface { return true }
        return settings.setsZ && !probesPocket
    }

    /// Whether the sizes the person typed (a pocket, a round boss) make sense.
    var entriesAreValid: Bool {
        let size = featureSize
        if probesPocket { return size.width > 0 && size.height > 0 && pocketDepth > 0 }
        if isRoundBoss { return bossDiameter > 0 }
        return true
    }

    // MARK: Moving through the steps

    var canAdvance: Bool {
        switch step {
            case .what: availableKinds.contains(kind) && entriesAreValid
            case .position, .probe: true
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

    /// The inset actually used: never more than a quarter of the smaller
    /// side, so a small stock still gets a point on it.
    static func clampedInset(_ requested: Double, width: Double, height: Double) -> Double {
        max(1, min(requested, width / 4, height / 4))
    }

    /// Where the probe tip should be jogged to (above the stock, or inside the
    /// pocket), in feature coordinates: origin at the bottom-left of the
    /// feature, X right, Y up. This is a target, not the probe's current
    /// position.
    func targetPoint(inset requested: Double) -> (x: Double, y: Double) {
        let size = featureSize
        let width = size.width
        let height = size.height
        let inset = Self.clampedInset(requested, width: width, height: height)

        switch kind {
            case .zSurface:
                // A disk with a hole has nothing to touch at its center.
                if case let .disk(outerDiameter, innerDiameter, _) = geometry, innerDiameter > 0 {
                    return (width / 2 + (outerDiameter + innerDiameter) / 4, height / 2)
                }
                return (width / 2, height / 2)
            case .point:
                let chosen = effectivePoint
                let x = chosen.column < 0 ? inset : (chosen.column > 0 ? width - inset : width / 2)
                let y = chosen.row < 0 ? inset : (chosen.row > 0 ? height - inset : height / 2)
                return (x, y)
        }
    }

    /// The points on the feature's outline the probe will touch, in feature
    /// coordinates. The drawing joins them to the dot with dashed lines.
    func touchPoints(inset requested: Double) -> [(x: Double, y: Double)] {
        let size = featureSize
        let target = targetPoint(inset: requested)

        return sides.map { side -> (x: Double, y: Double) in
            switch side {
                case .left: return (0, target.y)
                case .right: return (size.width, target.y)
                case .bottom: return (target.x, 0)
                case .top: return (target.x, size.height)
            }
        }
    }

    /// What the person has to do on the position step.
    func instructions(settings: ProbeSettings) -> [String] {
        let size = featureSize
        let inset = Self.clampedInset(settings.startInset, width: size.width, height: size.height)
        var steps = ["Put the probe (T\(settings.probeTool)) in the spindle and check that it triggers when you touch the tip."]

        let thing = isInside ? (hasHole ? "hole" : "pocket") : "stock"
        switch kind {
            case .zSurface:
                if probesPocket {
                    steps.append("Jog the tip above the dot, inside the pocket.")
                } else {
                    steps.append("Jog the tip above the dot, a few millimeters above the stock.")
                }
            case .point:
                let chosen = effectivePoint
                let title = chosen.title(inside: isInside).lowercased()
                if chosen.isCenter {
                    steps.append("Jog the tip above the dot in the middle of the \(centerSubject).")
                } else if chosen.isCorner {
                    steps.append("Jog the tip above the dot at the \(title) of the \(thing), \(Self.mm(inset)) mm from both \(isInside ? "walls" : "sides").")
                } else {
                    steps.append("Jog the tip above the dot at the \(title) of the \(thing), \(Self.mm(inset)) mm from it.")
                }
        }

        steps.append("Stay within about 2 mm of the dot in X and Y. The height does not need to be exact, but keep the tip clear of the \(isInside ? "pocket floor" : "stock").")

        if probesInsideHole {
            steps.append("The top is touched on the ring around the hole first, then the probe comes back to the hole.")
        } else if probesPocket {
            if kind == .point {
                steps.append("The floor is touched first, only to know the height. The walls are then touched \(Self.mm(wallHeight(settings: settings))) mm above it.")
            }
        } else if probesZFirst {
            let depth = settings.edgeDepth(forStockThickness: thickness)
            steps.append("The top is touched first. The sides are then touched \(Self.mm(depth)) mm below it, starting \(Self.mm(settings.outsideClearance)) mm outside the edge.")
        }
        return steps
    }

    /// How far above the pocket's floor its walls are touched.
    func wallHeight(settings: ProbeSettings) -> Double {
        settings.edgeDepth(forStockThickness: pocketDepth)
    }

    /// 10 → "10", 1.5 → "1.5".
    static func mm(_ value: Double) -> String {
        String(format: "%g", value)
    }

    // MARK: Text

    private var centerSubject: String {
        switch (isInside, shape) {
            case (false, .circle): "round stock"
            case (false, .rectangle): "stock"
            case (true, _): hasHole ? "hole" : "pocket"
        }
    }

    /// Where the work origin ends up, for the summary line.
    var originDescription: String {
        let chosen = effectivePoint
        let thing = isInside ? (hasHole ? "hole" : "pocket") : "stock"

        switch kind {
            case .zSurface:
                return probesPocket ? "Sets Z0 on the floor of the pocket." : "Sets Z0 on the top of the stock."
            case .point:
                if chosen.isCenter {
                    return "Sets X0 Y0 at the center of the \(centerSubject)\(zSuffix)."
                }
                if chosen.isCorner {
                    return "Sets X0 Y0 at the \(chosen.title(inside: isInside).lowercased()) of the \(thing)\(zSuffix)."
                }
                let axis = chosen.column != 0 ? "X0" : "Y0"
                return "Sets \(axis) on the \(chosen.title(inside: isInside).lowercased()) of the \(thing)\(zSuffix)."
        }
    }

    /// ", and Z0 on its top" for the summaries. A pocket does not set Z0.
    private var zSuffix: String { probesPocket ? "" : ", and Z0 on its top" }

    /// One or two sentences on what will happen, shown on the first step.
    var summary: String {
        var text = originDescription
        if probesPocket, kind == .point {
            text += " The floor is touched first to know the height; Z0 is left alone."
        } else if probesZFirst {
            text += " The top is touched first, because the sides are touched below it."
        }
        return text
    }
}
