//
//  ProbeCycle.swift
//  Stratum CNC
//
//  The vocabulary of the 3D probing dialog: what is probed, on what surface,
//  and which point of it. Pure values, no UI and no machine.
//

import Foundation

/// What the probe is looking for.
enum ProbeKind: String, CaseIterable, Identifiable, Codable {
    /// A height: the top of the stock, or the floor of a pocket.
    case zSurface
    /// A position in X and/or Y: a corner, a side or the center. Which one is
    /// chosen on the drawing (`ProbePoint`).
    case point

    var id: String { rawValue }

    var title: String {
        switch self {
            case .zSurface: "Z surface"
            case .point: "X / Y point"
        }
    }

    var systemImage: String {
        switch self {
            case .zSurface: "arrow.down.to.line"
            case .point: "scope"
        }
    }

    func subtitle(surface: ProbeSurface) -> String {
        switch self {
            case .zSurface:
                return surface == .inside ? "The floor of the pocket sets Z0" : "Top of the stock sets Z0"
            case .point:
                return "A corner, a side or the center. You pick it on the drawing"
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

/// Which side of the surface the probe works on: the outside of the stock
/// (touched from outside, moving in), or the inside of a pocket or hole
/// (touched from inside, moving out).
enum ProbeSurface: String, CaseIterable, Identifiable, Codable {
    case outside
    case inside

    var id: String { rawValue }

    func title(hasHole: Bool) -> String {
        switch self {
            case .outside: "Stock (outside)"
            case .inside: hasHole ? "Hole (inside)" : "Pocket (inside)"
        }
    }
}

/// The nine points of a rectangle that can be chosen on the drawing: four
/// corners, four side midpoints and the center. Seen from above, X to the
/// right, Y up.
enum ProbePoint: String, CaseIterable, Identifiable, Codable {
    case bottomLeft
    case bottom
    case bottomRight
    case left
    case center
    case right
    case topLeft
    case top
    case topRight

    var id: String { rawValue }

    /// −1 left, 0 middle, +1 right.
    var column: Int {
        switch self {
            case .bottomLeft, .left, .topLeft: -1
            case .bottom, .center, .top: 0
            case .bottomRight, .right, .topRight: 1
        }
    }

    /// −1 bottom, 0 middle, +1 top.
    var row: Int {
        switch self {
            case .bottomLeft, .bottom, .bottomRight: -1
            case .left, .center, .right: 0
            case .topLeft, .top, .topRight: 1
        }
    }

    var isCorner: Bool { column != 0 && row != 0 }
    var isCenter: Bool { self == .center }

    /// The point at `column`, `row` (each −1, 0 or +1).
    static func at(column: Int, row: Int) -> ProbePoint {
        allCases.first { $0.column == column && $0.row == row } ?? .center
    }

    func title(inside: Bool) -> String {
        let part = inside ? "wall" : "side"
        switch self {
            case .bottomLeft: return "Bottom-left corner"
            case .bottomRight: return "Bottom-right corner"
            case .topLeft: return "Top-left corner"
            case .topRight: return "Top-right corner"
            case .left: return "Left \(part)"
            case .right: return "Right \(part)"
            case .bottom: return "Bottom \(part)"
            case .top: return "Top \(part)"
            case .center: return "Center"
        }
    }
}

/// Sides as seen from above: X to the right, Y up.
enum ProbeEdge: String, CaseIterable, Identifiable, Codable {
    case left
    case right
    case bottom
    case top

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var axis: ProbeAxis {
        switch self {
            case .left, .right: .x
            case .bottom, .top: .y
        }
    }
}
