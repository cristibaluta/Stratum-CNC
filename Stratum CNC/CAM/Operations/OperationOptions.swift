//
//  OperationOptions.swift
//  Stratum CNC
//
//  Small option enums used by `OperationSettings`.
//

import Foundation
import StratumCAM

// MARK: - Small option enums

enum CutDirectionOption: String, CaseIterable, Codable, Hashable {
    case climb = "Climb"
    case conventional = "Conventional"
}

enum ThreadHandedness: String, CaseIterable, Codable, Hashable {
    case rightHand = "Right-hand"
    case leftHand = "Left-hand"
}

/// How a pocket is cleared. Mirrors StratumCAM's `SC.PocketClearingPattern`.
enum PocketPattern: String, CaseIterable, Codable, Hashable {
    case offset = "Offset"
    case raster = "Raster"
    case spiral = "Spiral"
    case trochoidal = "Trochoidal"
    case concentric = "Concentric"
    case adaptive = "Adaptive"
}

extension PocketPattern {

    /// The app's pattern for one of the library's (its parameters are kept in `OperationSettings`).
    init(_ pattern: SC.PocketClearingPattern) {
        switch pattern {
            case .offset:     self = .offset
            case .concentric: self = .concentric
            case .raster:     self = .raster
            case .spiral:     self = .spiral
            case .trochoidal: self = .trochoidal
            case .adaptive:   self = .adaptive
        }
    }
}

enum SpiralOrder: String, CaseIterable, Codable, Hashable {
    case outsideIn = "Outside in"
    case insideOut = "Inside out"
}

/// What the selected shape means for a slot.
enum SlotSource: String, CaseIterable, Codable, Hashable {
    /// The drawn slot walls: a straight-sided rectangle as wide as the tool.
    case outline = "Slot outline"
    /// The line the tool centre follows.
    case centerline = "Centre line"
}
