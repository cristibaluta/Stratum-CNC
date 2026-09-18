//
//  ToolSpec.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import Foundation

/// A machining tool's physical specs, assignable to a `T` number found in a
/// loaded program.
///
/// TODO: this is a hardcoded stand-in for a real tool library (e.g. loaded
/// from a user-editable file or synced from a CAM project). `ToolSpec.library`
/// below is just enough to pick from for now.
struct ToolSpec: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let diameterMM: Double
    let flutes: Int
    let kind: Kind
    /// Included (full) tip angle in degrees, for tools whose cutting profile
    /// is a cone rather than a flat or spherical bottom (`.vBit`, some
    /// `.engraver` bits). `nil` for tools where this doesn't apply, or where
    /// it hasn't been specified yet.
    var tipAngleDegrees: Double? = nil

    enum Kind: String {
        case endMill = "End Mill"
        case ballNose = "Ball Nose"
        case vBit = "V-Bit"
        case drill = "Drill"
        case engraver = "Engraver"
    }

    var summary: String {
        let diameter = diameterMM.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fmm", diameterMM)
            : String(format: "%.2fmm", diameterMM)
        return "\(diameter) \(kind.rawValue)"
    }
}

extension ToolSpec {
    static let library: [ToolSpec] = [
        ToolSpec(name: "1/8\" Flat End Mill", diameterMM: 3.175, flutes: 2, kind: .endMill),
        ToolSpec(name: "1/4\" Flat End Mill", diameterMM: 6.35, flutes: 2, kind: .endMill),
        ToolSpec(name: "3/8\" Flat End Mill", diameterMM: 9.525, flutes: 2, kind: .endMill),
        ToolSpec(name: "1/8\" Ball Nose", diameterMM: 3.175, flutes: 2, kind: .ballNose),
        ToolSpec(name: "1/4\" Ball Nose", diameterMM: 6.35, flutes: 2, kind: .ballNose),
        ToolSpec(name: "60° V-Bit", diameterMM: 6.35, flutes: 1, kind: .vBit, tipAngleDegrees: 60),
        ToolSpec(name: "90° V-Bit", diameterMM: 6.35, flutes: 1, kind: .vBit, tipAngleDegrees: 90),
        ToolSpec(name: "0.8mm Engraving Bit", diameterMM: 0.8, flutes: 1, kind: .engraver, tipAngleDegrees: 30),
        ToolSpec(name: "1/8\" Drill Bit", diameterMM: 3.175, flutes: 2, kind: .drill),
        ToolSpec(name: "1/4\" Drill Bit", diameterMM: 6.35, flutes: 2, kind: .drill),
    ]
}
