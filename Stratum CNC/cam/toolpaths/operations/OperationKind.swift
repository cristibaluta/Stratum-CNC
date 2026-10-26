//
//  OperationKind.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.10.2026.
//

import Foundation

enum OperationKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case contour
    case pocket
    case facing
    case slotting
    case engrave
    case drilling
    case counterbore
    case boring
    case threadMilling
    case chamfer

    var id: String {
        rawValue
    }

    /// The order and grouping used by the picker menu.
    static let groups: [[OperationKind]] = [
        [.contour, .pocket, .facing, .slotting, .engrave],
        [.drilling, .counterbore, .boring, .threadMilling],
        [.chamfer]
    ]

    var title: String {
        switch self {
            case .contour:       return "Contour"
            case .pocket:        return "Pocket"
            case .facing:        return "Facing"
            case .slotting:      return "Slot"
            case .engrave:       return "Engrave"
            case .drilling:      return "Drill"
            case .counterbore:   return "Counterbore"
            case .boring:        return "Bore"
            case .threadMilling: return "Thread mill"
            case .chamfer:       return "Chamfer"
        }
    }

    /// SF Symbol shown next to the title in the picker.
    var symbol: String {
        switch self {
            case .contour:       return "square.dashed"
            case .pocket:        return "square.inset.filled"
            case .facing:        return "rectangle.compress.vertical"
            case .slotting:      return "capsule"
            case .engrave:       return "pencil.tip"
            case .drilling:      return "smallcircle.filled.circle"
            case .counterbore:   return "circle.circle"
            case .boring:        return "circle.dashed"
            case .threadMilling: return "screwdriver"
            case .chamfer:       return "diamond"
        }
    }

    /// What to select on the canvas for this operation.
    var selectionHint: String? {
        switch self {
            case .contour:
                return "Select contour to detach the part from the stock material."
            case .pocket:
                return "Select closed shapes to clear inside."
            case .facing:
                return "Covers the bounding box of the selection."
            case .slotting:
                return nil   // depends on the slot source, see OperationOptionsView
            case .engrave:
                return "Follows the selected lines and text."
            case .drilling:
                return "Drills at a selected point or circle, or at the centre of any closed shape."
            case .counterbore, .boring:
                return "Select a point or a closed circle."
            case .threadMilling:
                return "Select and existing hole. Needs a threading bit."
            case .chamfer:
                return "Bevels the selected edges. Needs a V-bit."
        }
    }

    // MARK: Which generic controls apply

    /// Steps down in several passes by the general Stepdown. Facing, drilling, boring and
    /// chamfering are a single pass; a slot has its own depth per pass; a thread steps by its pitch.
    var usesStepdown: Bool {
        switch self {
            case .contour, .pocket, .engrave, .counterbore: return true
            default: return false
        }
    }

    var usesStepover: Bool {
        switch self {
            case .pocket, .counterbore: return true
            default: return false
        }
    }

    /// The counterbore has its own depth and a chamfer's depth comes from its width and the
    /// V-bit's angle, so the general End Z field is hidden for them.
    var usesEndZ: Bool {
        switch self {
            case .counterbore, .chamfer: return false
            default: return true
        }
    }

    /// "<Title> N" with the lowest free N among `existingNames`, so auto-generated
    /// toolpath names stay distinguishable within their own operation category
    /// (`Contour 1`, `Contour 2`, `Pocket 1`, ...) instead of sharing one counter
    /// across every kind of operation.
    func nextName(among existingNames: Set<String>) -> String {
        var number = 1
        while existingNames.contains("\(title) \(number)") {
            number += 1
        }
        return "\(title) \(number)"
    }
}

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
