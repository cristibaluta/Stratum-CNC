//
//  ProbeFlow.swift
//  Stratum CNC
//
//  The state and rules of the 3D probing dialog: which step it is on, what is
//  being probed, and where the probe should be jogged to. Pure state;
//  `ProbeSheet` presents it. Same split as `BitChangeFlow` / `BitChangeSheet`.
//
//  Stock coordinates used here: origin at the stock's bottom-left corner seen
//  from above, X to the right, Y up, millimeters.
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

    var kind: ProbeKind
    var circleSide: CircleSide
    var corner: ProbeCorner = .bottomLeft
    var edge: ProbeEdge = .left

    init(geometry: StockGeometry) {
        self.geometry = geometry
        circleSide = Self.defaultCircleSide(for: geometry)
        kind = Self.defaultShape(for: geometry) == .circle ? .center : .corner
    }

    /// Follows the stock; it is not chosen. The center is one of the kinds.
    var shape: ProbeShape { Self.defaultShape(for: geometry) }

    /// A disk with a hole can be probed from outside or from inside.
    var hasHole: Bool {
        if case let .disk(_, innerDiameter, _) = geometry { return innerDiameter > 0 }
        return false
    }

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
    static func defaultCircleSide(for geometry: StockGeometry) -> CircleSide {
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

    /// What can be probed on the chosen shape. A circle has no corners or
    /// straight edges.
    var availableKinds: [ProbeKind] {
        switch shape {
            case .rectangle: ProbeKind.allCases
            case .circle: [.zSurface, .center]
        }
    }

    var needsCorner: Bool { kind == .corner }
    var needsEdge: Bool { kind == .edge }
    var needsCircleSide: Bool { shape == .circle && kind == .center && hasHole }

    /// X and Y both need Z first: the sides are touched at a depth below the top.
    var probesZFirst: Bool { kind != .zSurface }

    // MARK: Moving through the steps

    var canAdvance: Bool {
        switch step {
            case .what: availableKinds.contains(kind)
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

    /// Where the probe tip should be jogged to (above the stock), in stock
    /// coordinates. This is a target, not the probe's current position.
    func targetPoint(inset requested: Double) -> (x: Double, y: Double) {
        let size = Self.footprint(of: geometry)
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
            case .edge:
                switch edge {
                    case .left: return (inset, height / 2)
                    case .right: return (width - inset, height / 2)
                    case .bottom: return (width / 2, inset)
                    case .top: return (width / 2, height - inset)
                }
            case .corner:
                return (corner.isLeft ? inset : width - inset,
                        corner.isBottom ? inset : height - inset)
            case .center:
                return (width / 2, height / 2)
        }
    }

    /// The points on the stock's outline the probe will touch, in stock
    /// coordinates. The drawing joins them to the dot with dashed lines.
    func touchPoints(inset requested: Double) -> [(x: Double, y: Double)] {
        let size = Self.footprint(of: geometry)
        let width = size.width
        let height = size.height
        let target = targetPoint(inset: requested)

        switch kind {
            case .zSurface:
                return []
            case .edge:
                switch edge {
                    case .left: return [(0, target.y)]
                    case .right: return [(width, target.y)]
                    case .bottom: return [(target.x, 0)]
                    case .top: return [(target.x, height)]
                }
            case .corner:
                return [(corner.isLeft ? 0 : width, target.y),
                        (target.x, corner.isBottom ? 0 : height)]
            case .center:
                var radiusX = width / 2
                var radiusY = height / 2
                if circleSide == .inside, case let .disk(_, innerDiameter, _) = geometry, innerDiameter > 0 {
                    radiusX = innerDiameter / 2
                    radiusY = innerDiameter / 2
                }
                let centerX = width / 2
                let centerY = height / 2
                return [(centerX - radiusX, centerY), (centerX + radiusX, centerY),
                        (centerX, centerY - radiusY), (centerX, centerY + radiusY)]
        }
    }

    /// True when the center is probed inside a hole, where Z can't be touched
    /// at the dot and is touched on the ring instead.
    var probesInsideHole: Bool { kind == .center && shape == .circle && circleSide == .inside && hasHole }

    /// What the person has to do on the position step.
    func instructions(settings: ProbeSettings) -> [String] {
        let size = Self.footprint(of: geometry)
        let inset = Self.clampedInset(settings.startInset, width: size.width, height: size.height)
        var steps = ["Put the probe (T\(settings.probeTool)) in the spindle and check that it triggers when you touch the tip."]

        switch kind {
            case .zSurface:
                steps.append("Jog the tip above the dot, a few millimeters above the stock.")
            case .edge:
                steps.append("Jog the tip above the dot on the \(edge.title.lowercased()) side, \(Self.mm(inset)) mm from the edge.")
            case .corner:
                steps.append("Jog the tip above the dot at the \(corner.title.lowercased()) corner, \(Self.mm(inset)) mm from both sides.")
            case .center:
                if shape == .rectangle {
                    steps.append("Jog the tip above the dot in the middle of the stock.")
                } else if probesInsideHole {
                    steps.append("Jog the tip above the dot in the middle of the hole.")
                } else {
                    steps.append("Jog the tip above the dot in the middle of the round stock.")
                }
        }

        steps.append("Stay within about 2 mm of the dot in X and Y. The height does not need to be exact, but keep the tip above the stock.")

        if probesInsideHole {
            steps.append("The top is touched on the ring around the hole first, then the probe comes back to the hole.")
        } else if probesZFirst {
            let depth = settings.edgeDepth(forStockThickness: thickness)
            steps.append("The top is touched first. The sides are then touched \(Self.mm(depth)) mm below it, starting \(Self.mm(settings.outsideClearance)) mm outside the edge.")
        }
        return steps
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
                "Sets Z0 on the top of the stock."
            case .edge:
                switch edge {
                    case .left, .right: "Sets X0 on the \(edge.title.lowercased()) side."
                    case .bottom, .top: "Sets Y0 on the \(edge.title.lowercased()) side."
                }
            case .corner:
                "Sets X0 Y0 Z0 at the \(corner.title.lowercased()) corner of the stock top."
            case .center:
                shape == .rectangle
                    ? "Sets X0 Y0 at the center of the stock, and Z0 on its top."
                    : "Sets X0 Y0 at the center of the \(circleSide == .outside ? "round stock" : "hole"), and Z0 on its top."
        }
    }

    /// One or two sentences on what will happen, shown on the first step.
    var summary: String {
        var text = originDescription
        if probesZFirst {
            text += " The top is touched first, because the sides are touched below it."
        }
        return text
    }
}
