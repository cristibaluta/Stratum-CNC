//
//  OperationOptions.swift
//  Stratum CNC
//
//  The app's labels for the library's option enums (`SC.CutDirection`, `SC.ThreadDirection`,
//  `SC.SpiralDirection`, `SC.PocketClearingPattern.Kind`), and the one option the library
//  doesn't have: what the selected shape means for a slot.
//

import Foundation
import StratumCAM

/// An option the user picks from a menu, with the name the menu shows for it.
protocol TitledOption {
    var title: String { get }
}

extension SC.CutDirection: TitledOption {
    var title: String {
        switch self {
            case .climb:        return "Climb"
            case .conventional: return "Conventional"
        }
    }

    /// The id of the option in the library's choice field (`SC.cutDirectionChoice`).
    var fieldID: String {
        rawValue
    }
}

extension SC.ThreadDirection: TitledOption {
    var title: String {
        switch self {
            case .rightHand: return "Right-hand"
            case .leftHand:  return "Left-hand"
        }
    }
}

extension SC.SpiralDirection: TitledOption {
    var title: String {
        switch self {
            case .outsideIn: return "Outside in"
            case .insideOut: return "Inside out"
        }
    }
}

extension SC.PocketClearingPattern.Kind: TitledOption {
    var title: String {
        switch self {
            case .offset:     return "Offset"
            case .raster:     return "Raster"
            case .spiral:     return "Spiral"
            case .trochoidal: return "Trochoidal"
            case .concentric: return "Concentric"
            case .adaptive:   return "Adaptive"
        }
    }
}

/// What the selected shape means for a slot.
enum SlotSource: String, CaseIterable, Codable, Hashable, TitledOption {
    /// The drawn slot walls: a straight-sided rectangle as wide as the tool.
    case outline = "Slot outline"
    /// The line the tool centre follows.
    case centerline = "Centre line"

    var title: String {
        rawValue
    }
}
