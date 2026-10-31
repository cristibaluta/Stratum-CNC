//
//  Tool+HeaderMatching.swift
//  Stratum CNC
//
//  Tools a G-code header declares are `Tool`s too, made from the few values a header carries.
//  They are never added to the library; where the library has a close match, the match is used instead.
//

import Foundation

extension Tool {

    /// A tool described only by what a CAM header says: no shank, length, quantity or presets.
    /// The shank stays 0, which the UI reads as "not known" (`shankDescription`). The length is left
    /// out on purpose: no header carries a trustworthy one, it comes from the library tool.
    init(fromHeader name: String, diameter: Double, type: ToolType, tipAngle: Double? = nil) {
        self.init(name: name,
                  shankDiameter: 0,
                  toolDiameter: diameter,
                  length: nil,
                  type: type,
                  tipAngle: tipAngle)
    }

    /// The library tool closest to this one, or `nil` when none is close enough: same kind of tool
    /// (`ToolType.matchingType`), diameter within a tolerance, and for tools with a tip angle on
    /// both sides, the angle within a tolerance. Among those, the one with the same name wins, then
    /// the smallest difference in diameter and angle.
    func closestLibraryTool(in library: [Tool]) -> Tool? {
        let diameterTolerance = 0.05
        let angleTolerance = 1.0

        let candidates: [(tool: Tool, sameName: Bool, distance: Double)] = library.compactMap { candidate in
            guard candidate.type.matchingType == type.matchingType else {
                return nil
            }
            let diameterDifference = abs(candidate.toolDiameter - toolDiameter)
            guard diameterDifference <= diameterTolerance else {
                return nil
            }
            var angleDifference = 0.0
            if let angle = tipAngle, let candidateAngle = candidate.tipAngle, candidateAngle > 0 {
                angleDifference = abs(candidateAngle - angle)
                guard angleDifference <= angleTolerance else {
                    return nil
                }
            }
            let sameName = candidate.name.caseInsensitiveCompare(name) == .orderedSame
            return (candidate, sameName, diameterDifference + angleDifference * 0.01)
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

    /// Header tools resolved against the library: each one that has a close library tool becomes
    /// that tool; the others stay as the header describes them (never added to the library).
    static func resolvingHeaderTools(_ headerTools: [Int: Tool], in library: [Tool]) -> [Int: Tool] {
        headerTools.mapValues { $0.closestLibraryTool(in: library) ?? $0 }
    }
}
