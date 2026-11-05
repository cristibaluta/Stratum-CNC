//
//  ProbeCycle.swift
//  Stratum CNC
//
//  The vocabulary of the 3D probing dialog: Z or XY, which of the four XY
//  features, and which corner of it. Pure values, no UI and no machine.
//

import Foundation

/// What the probe is looking for.
enum ProbeKind: String, CaseIterable, Identifiable, Codable {
    /// A height: whatever surface is under the tip (the top of the stock, or
    /// the floor of a pocket). No options.
    case zSurface
    /// A position in X and Y: one of the four `ProbeFeature`s.
    case point

    var id: String { rawValue }

    var title: String {
        switch self {
            case .zSurface: "Z"
            case .point: "XY"
        }
    }
}

/// The four things the XY probe can find. The probe is never told a size:
/// it jogs out from where the tip was left until it touches.
enum ProbeFeature: String, CaseIterable, Identifiable, Codable {
    case bossCorner
    case pocketCorner
    case bossCenter
    case pocketCenter

    var id: String { rawValue }

    var title: String {
        switch self {
            case .bossCorner: "Find Boss Corner"
            case .pocketCorner: "Find Pocket Corner"
            case .bossCenter: "Find Boss Center"
            case .pocketCenter: "Find Pocket Center"
        }
    }

    /// Touched from inside, moving out (a pocket or hole), as opposed to from
    /// outside, moving in (a boss, or the stock itself).
    var isInside: Bool { self == .pocketCorner || self == .pocketCenter }
    var isCenter: Bool { self == .bossCenter || self == .pocketCenter }

    var thing: String { isInside ? "pocket" : "boss" }
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
