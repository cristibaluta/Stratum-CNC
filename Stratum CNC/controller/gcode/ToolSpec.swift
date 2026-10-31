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
    /// A spec made from a tools-library tool carries that tool's id (see `init(from:)`); any
    /// other spec gets a fresh one.
    var id = UUID()
    let name: String
    let diameterMM: Double
    let flutes: Int
    let kind: Kind
    /// Included (full) tip angle in degrees, for tools whose cutting profile
    /// is a cone rather than a flat or spherical bottom (`.vBit`, some
    /// `.engraver` bits). `nil` for tools where this doesn't apply, or where
    /// it hasn't been specified yet.
    var tipAngleDegrees: Double? = nil
    /// Cutting length in millimeters, from the tools-library tool this spec was made from
    /// (`init(from:)`). Never read from G-code. `nil` when there is no library tool or it has
    /// no length. Use `drawnLengthMM` for what the canvas shows.
    var lengthMM: Double? = nil

    /// What is drawn when the length is missing or not usable.
    static let fallbackLengthMM: Double = 12

    /// How tall the canvas draws the tool above its tip: the library's length, or
    /// `fallbackLengthMM` when that is missing, zero, negative or not a number.
    var drawnLengthMM: Double {
        guard let lengthMM, lengthMM.isFinite, lengthMM > 0 else {
            return Self.fallbackLengthMM
        }
        return lengthMM
    }

    enum Kind: String {
        case endMill = "End Mill"
        case ballNose = "Ball Nose"
        case vBit = "V-Bit"
        case drill = "Drill"
        case engraver = "Engraver"
        case threadMill = "Thread Mill"
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

extension ToolSpec {

    /// The spec of a library tool. It keeps the tool's id, so the assignment stays tied to
    /// the library entry, and takes its length, which no G-code header carries.
    init(from tool: Tool) {
        self.init(id: tool.id,
                  name: tool.name,
                  diameterMM: tool.toolDiameter,
                  flutes: ToolSpec.assumedFlutes,
                  kind: Kind(toolType: tool.type),
                  tipAngleDegrees: (tool.tipAngle ?? 0) > 0 ? tool.tipAngle : nil,
                  lengthMM: tool.length)
    }

    /// The library tool closest to this spec, or `nil` when none is close enough: same kind
    /// of tool, diameter within `diameterTolerance`, and for tools with a tip angle on both
    /// sides, the angle within `angleTolerance`. Among those, the one with the same name wins,
    /// then the smallest difference in diameter and angle.
    func closestLibraryTool(in tools: [Tool]) -> Tool? {
        let diameterTolerance = 0.05
        let angleTolerance = 1.0

        let candidates: [(tool: Tool, sameName: Bool, distance: Double)] = tools.compactMap { tool in
            guard Kind(toolType: tool.type) == kind else {
                return nil
            }
            let diameterDifference = abs(tool.toolDiameter - diameterMM)
            guard diameterDifference <= diameterTolerance else {
                return nil
            }
            var angleDifference = 0.0
            if let angle = tipAngleDegrees, let toolAngle = tool.tipAngle, toolAngle > 0 {
                angleDifference = abs(toolAngle - angle)
                guard angleDifference <= angleTolerance else {
                    return nil
                }
            }
            let sameName = tool.name.caseInsensitiveCompare(name) == .orderedSame
            return (tool, sameName, diameterDifference + angleDifference * 0.01)
        }

        return candidates
            .min { a, b in
                if a.sameName != b.sameName {
                    return a.sameName
                }
                return a.distance < b.distance
            }?
            .tool
    }

    /// Header tools resolved against the library: each one that has a close library tool
    /// becomes that tool's spec; the others stay as the header describes them (an
    /// instance made from the known values, which is never added to the library).
    static func resolvingHeaderTools(_ headerTools: [Int: ToolSpec], in library: [Tool]) -> [Int: ToolSpec] {
        headerTools.mapValues { spec in
            spec.closestLibraryTool(in: library).map(ToolSpec.init(from:)) ?? spec
        }
    }
}

extension ToolSpec.Kind {

    init(toolType: ToolType) {
        switch toolType {
            case .endMill, .corn, .solderMaskRemover: self = .endMill
            case .ballNose:                           self = .ballNose
            case .vBit, .chamfer:                     self = .vBit
            case .engraving:                          self = .engraver
            case .drill:                              self = .drill
            case .threadMill:                         self = .threadMill
        }
    }
}
