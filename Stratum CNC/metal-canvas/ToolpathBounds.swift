//
//  ToolpathBounds.swift
//  Stratum CNC
//
//  Pure math, like `ToolFootprint`: given a program's segments and the tool
//  radius in effect on each line, what rectangle does the finished job
//  occupy in XY. No scene or rendering types here.
//

import Foundation
import simd

/// Axis-aligned XY rectangle around a program's cutting moves, in
/// millimeters and in *toolpath* coordinates (before `xyOffset`).
struct ToolpathBounds: Equatable {
    /// Bottom-left corner — the job's origin, the point the canvas's XY
    /// offset positions.
    var min: SIMD2<Float>
    /// Top-right corner.
    var max: SIMD2<Float>

    var size: SIMD2<Float> { max - min }

    /// The bounds of `segments`' cutting moves, each grown by the radius of
    /// the tool that makes it.
    ///
    /// Growing per segment, rather than adding one radius to the plain
    /// bounds, is what makes the rectangle follow the *outer contour*: with
    /// a 6 mm roughing tool inside and a 3 mm finishing tool on the outline,
    /// each edge ends up where the tool reaching furthest out leaves it, not
    /// where the biggest tool in the file happens to be.
    ///
    /// Rapids are left out — they're travel, not material removed — so a
    /// park move off to the side doesn't stretch the box.
    ///
    /// - Parameter toolRadii: tool radius in effect on each line, indexed by
    ///   1-based G-code line number (index 0 unused). A segment whose line
    ///   falls outside the array uses radius 0.
    /// - Returns: `nil` when there are no cutting moves.
    static func compute(segments: [ToolpathSegment], toolRadii: [Float]) -> ToolpathBounds? {
        var minPoint = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maxPoint = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false

        for segment in segments where segment.flags & ToolpathFlags.rapid == 0 {
            let line = Int(segment.lineNumber)
            let radius = line < toolRadii.count ? toolRadii[line] : 0
            let radii = SIMD2<Float>(repeating: radius)

            let start = SIMD2<Float>(segment.start.x, segment.start.y)
            let end = SIMD2<Float>(segment.end.x, segment.end.y)

            minPoint = simd_min(minPoint, simd_min(start, end) - radii)
            maxPoint = simd_max(maxPoint, simd_max(start, end) + radii)
            found = true
        }

        return found ? ToolpathBounds(min: minPoint, max: maxPoint) : nil
    }
}
