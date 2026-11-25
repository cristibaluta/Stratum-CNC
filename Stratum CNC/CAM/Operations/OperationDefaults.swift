//
//  OperationDefaults.swift
//  Stratum CNC
//
//  Starting values for the general toolpath fields (End Z, Stepdown, Stepover) that make
//  sense for each operation. A value is only offered for a field the operation actually
//  uses (see `SC.MachiningOperation.requirements`).
//
//  A default never overrides the user: nothing is recorded about what was edited. A field
//  still holds the previous operation's default when it is untouched, so only those follow
//  the new operation's defaults; any other value is the user's (or a tool preset's) and stays.
//
//  The options that belong to one operation only (pocket pattern, thread pitch, chamfer
//  width…) have their defaults in `OperationSettings` and are kept per operation anyway.
//

import Foundation
import StratumCAM

struct OperationDefaults {
    /// Depth of the cut, mm (negative is below the surface).
    var endZ: Double?
    /// Depth per pass, mm.
    var stepDown: Double?
    /// Width per pass as a fraction of the tool diameter.
    var stepOverFraction: Double?
}

extension SC.MachiningOperation.Kind {

    var defaults: OperationDefaults {
        switch self {
            case .contour:
                return OperationDefaults(endZ: -1, stepDown: 0.5)
            case .pocket:
                return OperationDefaults(endZ: -1, stepDown: 0.5, stepOverFraction: 0.4)
            case .pocket3D:
                return OperationDefaults(endZ: -1, stepDown: 0.5, stepOverFraction: 0.4)
            case .facing:
                return OperationDefaults(endZ: -0.3, stepDown: 0.3, stepOverFraction: 0.8)
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

    /// Switches End Z, Stepdown and Stepover from `oldKind`'s defaults to `kind`'s. A field that
    /// isn't at the old default was changed (by the user or a tool preset) and is left alone, and
    /// so is one `kind` doesn't use. Without an `oldKind` (a new toolpath) every field is set.
    mutating func applyDefaults(for kind: SC.MachiningOperation.Kind, replacing oldKind: SC.MachiningOperation.Kind? = nil) {
        let defaults = kind.defaults
        let old = oldKind?.defaults

        func isUntouched(_ value: Double, _ oldDefault: Double?) -> Bool {
            guard oldKind != nil else {
                return true
            }
            return oldDefault.map { abs(value - $0) < 1e-6 } ?? true
        }

        if let endZ = defaults.endZ, isUntouched(self.endZ, old?.endZ) {
            self.endZ = endZ
        }
        if let stepDown = defaults.stepDown, isUntouched(self.stepDown, old?.stepDown) {
            self.stepDown = stepDown
        }
        if let fraction = defaults.stepOverFraction, isUntouched(stepOverPercent, old?.stepOverFraction.map { $0 * 100 }) {
            stepOverPercent = Self.clampedStepOver(fraction * 100)
        }
    }
}
