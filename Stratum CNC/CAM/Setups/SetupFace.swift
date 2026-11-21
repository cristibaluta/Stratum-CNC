//
//  SetupFace.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.11.2026.
//

import Foundation

/// The orientations the app offers today. A setup stores an angle and an axis, not a face, so a
/// rotary axis can add other angles without a migration.
enum SetupFace: String, Codable, CaseIterable, Identifiable, Sendable {
    case top
    case front
    case bottom
    case back
    case left
    case right

    var id: Self {
        self
    }

    var angle: Double {
        switch self {
            case .top:            return 0
            case .front, .left:   return 90
            case .bottom:         return 180
            case .back, .right:   return 270
        }
    }

    /// The axis that reaches this face. The bottom can be reached about either: this is its default.
    var axis: SetupAxis {
        switch self {
            case .left, .right: return .y
            default:            return .x
        }
    }

    /// The faces that can be reached about more than one axis: which one decides what mirrors.
    var hasChoiceOfAxis: Bool {
        self == .bottom
    }

    /// The side faces stand the stock on its edge: they need a 3D model to make sense of.
    var isSide: Bool {
        switch self {
            case .front, .back, .left, .right: return true
            default:                           return false
        }
    }

    var title: String {
        self.rawValue.capitalized
    }

    var persistedName: String {
        self.rawValue
    }

    /// The face a stored rotation is (to the nearest degree), or nil for an angle between faces.
    init?(angle: Double, axis: SetupAxis = .x) {
        let normalized = Setup.normalized(angle)
        guard let face = SetupFace.allCases.first(where: {
            abs($0.angle - normalized) < 0.5 && ($0.axis == axis || $0.hasChoiceOfAxis || $0 == .top)
        }) else {
            return nil
        }
        self = face
    }

    init?(persistedName: String) {
        guard let face = Self.allCases.first(where: { $0.persistedName == persistedName }) else {
            return nil
        }
        self = face
    }
}
