//
//  ProbeCycle.swift
//  Stratum CNC
//
//  The vocabulary of the 3D probing dialog: what is probed, on what shape,
//  and which corner or edge. Pure values, no UI and no machine.
//

import Foundation

/// What the probe is looking for.
enum ProbeKind: String, CaseIterable, Identifiable, Codable {
    case zSurface
    case edge
    case corner
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
            case .zSurface: "Z surface"
            case .edge: "Edge"
            case .corner: "Corner"
            case .center: "Center"
        }
    }

    var systemImage: String {
        switch self {
            case .zSurface: "arrow.down.to.line"
            case .edge: "rectangle.lefthalf.filled"
            case .corner: "square.dashed.inset.filled"
            case .center: "scope"
        }
    }

    func subtitle(shape: ProbeShape) -> String {
        switch self {
            case .zSurface:
                return "Top of the stock sets Z0"
            case .edge:
                return "One side sets X0 or Y0"
            case .corner:
                return "Top and two sides set X0 Y0 Z0"
            case .center:
                return shape == .rectangle
                    ? "Both sides of X and Y give the middle"
                    : "Four touches give the center and diameter"
        }
    }
}

/// The footprint being probed, seen from above.
enum ProbeShape: String, CaseIterable, Identifiable, Codable {
    case rectangle
    case circle

    var id: String { rawValue }

    var title: String {
        switch self {
            case .rectangle: "Rectangle"
            case .circle: "Circle"
        }
    }
}

/// For a circle: probe the outside of a round stock, or the inside of a hole.
enum CircleSide: String, CaseIterable, Identifiable, Codable {
    case outside
    case inside

    var id: String { rawValue }

    var title: String {
        switch self {
            case .outside: "Outside (boss)"
            case .inside: "Inside (hole)"
        }
    }
}

/// Corners as seen from above: X to the right, Y up.
enum ProbeCorner: String, CaseIterable, Identifiable, Codable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight

    var id: String { rawValue }

    var title: String {
        switch self {
            case .bottomLeft: "Bottom-left"
            case .bottomRight: "Bottom-right"
            case .topLeft: "Top-left"
            case .topRight: "Top-right"
        }
    }

    var isLeft: Bool { self == .bottomLeft || self == .topLeft }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
}

/// Sides as seen from above: X to the right, Y up.
enum ProbeEdge: String, CaseIterable, Identifiable, Codable {
    case left
    case right
    case bottom
    case top

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
}
