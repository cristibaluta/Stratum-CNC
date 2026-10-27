//
//  OperationDefaults.swift
//  Stratum CNC
//
//  Starting values for the general toolpath fields (End Z, Stepdown, Stepover) that make
//  sense for each operation. A value is only offered for a field the operation actually
//  uses (see `SC.MachiningOperation.requirements`).
//
//  A default never overrides the user: once a field has been edited it is recorded in
//  `ToolpathData.editedFields` and keeps its value when the operation changes. Fields still
//  untouched follow the operation's defaults.
//
//  The options that belong to one operation only (pocket pattern, thread pitch, chamfer
//  width…) have their defaults in `OperationSettings` and are kept per operation anyway.
//

import Foundation

/// The general fields whose default depends on the operation.
enum ToolpathField: String, Codable, Hashable {
    case endZ
    case stepDown
    case stepOver
}

struct OperationDefaults {
    /// Depth of the cut, mm (negative is below the surface).
    var endZ: Double?
    /// Depth per pass, mm.
    var stepDown: Double?
    /// Width per pass as a fraction of the tool diameter.
    var stepOverFraction: Double?
}

extension OperationKind {

    var defaults: OperationDefaults {
        switch self {
            case .contour:
                return OperationDefaults(endZ: -1, stepDown: 0.5)
            case .pocket:
                return OperationDefaults(endZ: -1, stepDown: 0.5, stepOverFraction: 0.4)
            case .facing:
                return OperationDefaults(endZ: -0.3)
            case .slotting:
                return OperationDefaults(endZ: -1)
            case .engrave:
                return OperationDefaults(endZ: -0.1, stepDown: 0.1)
            case .drilling, .boring, .threadMilling:
                return OperationDefaults(endZ: -3)
            case .counterbore:
                return OperationDefaults(stepDown: 0.5, stepOverFraction: 0.4)
            case .chamfer:
                return OperationDefaults()
        }
    }
}

extension ToolpathData {

    /// Sets End Z, Stepdown and Stepover to `kind`'s defaults, except the ones the user has
    /// edited and the ones `kind` doesn't use.
    mutating func applyDefaults(for kind: OperationKind) {
        let defaults = kind.defaults

        if !editedFields.contains(.endZ), let endZ = defaults.endZ {
            self.endZ = endZ
        }
        if !editedFields.contains(.stepDown), let stepDown = defaults.stepDown {
            self.stepDown = stepDown
        }
        if !editedFields.contains(.stepOver), let fraction = defaults.stepOverFraction {
            stepOverPercent = Self.clampedStepOver(fraction * 100)
        }
    }

    /// Remembers that the user chose `field`'s value, so a later change of operation keeps it.
    mutating func markEdited(_ field: ToolpathField) {
        editedFields.insert(field)
    }
}
