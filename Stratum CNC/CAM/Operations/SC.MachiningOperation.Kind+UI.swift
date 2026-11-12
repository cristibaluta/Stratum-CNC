//
//  SC.MachiningOperation.Kind+UI.swift
//  Stratum CNC
//
//  What the app shows for each kind of StratumCAM operation: its name, icon, help text and
//  place in the picker. The kinds themselves come from the library (`SC.MachiningOperation.Kind`).
//

import Foundation
import StratumCAM

extension SC.MachiningOperation {
    /// Display name for the operation (the same short name as its kind's `title`).
    public var displayName: String {
        kind.title
    }
}

extension SC.MachiningOperation.Kind {

    /// The order and grouping used by the picker menu. A rest toolpath isn't in it: it needs a
    /// source pocket, so it's made with "Create rest operation" on a pocket
    /// (see `OperationSettings.isRest`).
    static let groups: [[SC.MachiningOperation.Kind]] = [
        [.facing],
        [.pocket, .pocket3D, .contour, .slotting],
        [.drilling, .counterbore, .boring, .threadMilling],
        [.engrave, .chamfer]
    ]

    var title: String {
        switch self {
            case .contour:       return "Contour"
            case .pocket:        return "Pocket"
            case .pocket3D:      return "Pocket 3D"
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
            case .pocket3D:      return "square.3.layers.3d.down.right"
            case .facing:        return "rectangle.compress.vertical"
            case .slotting:      return "capsule"
            case .engrave:       return "scribble"
            case .drilling:      return "smallcircle.filled.circle"
            case .counterbore:   return "circle.circle"
            case .boring:        return "circle.dashed"
            case .threadMilling: return "screwdriver"
            case .chamfer:       return "diamond"
        }
    }

    /// What the operation does and what to select for it, shown next to its title in the
    /// picker.
    var summary: String {
        switch self {
            case .contour:
                return "Cuts along the edge of a shape, inside, outside or on the line. Select the contour to detach the part from the stock."
            case .pocket:
                return "Clears the material inside a closed shape. Select closed shapes."
            case .pocket3D:
                return "Clears the material inside a closed shape from top to bottom by avoiding obstacles as they appear."
            case .facing:
                return "Levels the top of the stock over the bounding box of the selection, or over the whole stock."
            case .slotting:
                return "Cuts a straight slot as wide as the tool. Select the slot outline or the line the tool centre follows."
            case .engrave:
                return "Follows lines and text at a shallow depth. Select lines or text."
            case .drilling:
                return "Drills straight down, with optional pecking. Select a point or circle, or any closed shape for its centre."
            case .counterbore:
                return "Widens the top of a hole to a set depth. Select a point or a closed circle."
            case .boring:
                return "Finishes a hole to an exact diameter. Select a point or a closed circle."
            case .threadMilling:
                return "Cuts a thread inside an existing hole, or on the outside of a stud when Internal is off. Select the hole or stud. Needs a thread mill."
            case .chamfer:
                return "Bevels the selected edges. Needs a V-bit."
        }
    }

    /// What to select on the canvas for this operation.
    var selectionHint: String? {
        switch self {
            case .contour:
                return "Select contour to detach the part from the stock material."
            case .pocket:
                return "Select closed shapes to clear inside."
            case .pocket3D:
                return "Select closed outer shape."
            case .facing:
                return "Covers the bounding box of the selection, or the whole stock."
            case .slotting:
                return nil   // depends on the slot source, see `selectionHint(slotSource:)`
            case .engrave:
                return "Follows the selected lines and text."
            case .drilling:
                return "Drills at a selected point or circle, or at the centre of any closed shape."
            case .counterbore, .boring:
                return "Select a point or a closed circle."
            case .threadMilling:
                return "Select an existing hole (or a stud for an external thread). Needs a thread mill."
            case .chamfer:
                return "Bevels the selected edges. Needs a V-bit."
        }
    }

    /// `selectionHint`, with the slot's text taken from what the selection is
    /// (the slot walls or the line the tool centre follows). Shown in the Shapes section.
    func selectionHint(slotSource: SlotSource) -> String? {
        guard self == .slotting else {
            return selectionHint
        }
        switch slotSource {
            case .outline:
                return "Select the slot outline: a straight-sided rectangle exactly as wide as the tool."
            case .centerline:
                return "Select the line the tool centre follows."
        }
    }

    /// "<Title> N" with the lowest free N among `existingNames`, so auto-generated
    /// toolpath names stay distinguishable within their own operation category
    /// (`Contour 1`, `Contour 2`, `Pocket 1`, ...) instead of sharing one counter
    /// across every kind of operation.
    func nextName(among existingNames: Set<String>) -> String {
        Self.nextName(titled: title, among: existingNames)
    }

    /// Same, for a title that isn't a kind's own (a rest toolpath's "Rest").
    static func nextName(titled title: String, among existingNames: Set<String>) -> String {
        var number = 1
        while existingNames.contains("\(title) \(number)") {
            number += 1
        }
        return "\(title) \(number)"
    }
}

