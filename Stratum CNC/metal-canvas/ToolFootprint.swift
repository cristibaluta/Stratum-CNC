//
//  ToolFootprint.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//


//
//  ToolFootprint.swift
//  Stratum CNC
//
//  M0 of the heightmap roadmap: pure tool-shape math, deliberately kept
//  free of grid indexing or toolpath traversal so it can be reasoned about
//  (and tested) as "given this tool and this offset, what Z does it leave
//  behind" — nothing more.
//

import Foundation

enum ToolFootprint {

    /// How far a tool's footprint reaches from its centerline in the XY
    /// plane. `HeightmapGrid.carve` uses this to limit which cells even need
    /// to be considered for a given segment.
    static func radius(for tool: ToolSpec) -> Float {
        Float(tool.diameterMM) / 2
    }

    /// The Z the tool's surface leaves behind at radial offset `d` from its
    /// centerline, given the tool's tip is currently at `tipZ`.
    ///
    /// Returns `nil` when `d` is outside the tool's footprint (radius) —
    /// meaning this tool, at this position, doesn't touch that offset at
    /// all, so the caller shouldn't lower anything.
    ///
    /// `d` and `tipZ` are both in millimeters, matching `ToolpathSegment`.
    static func surfaceZ(for tool: ToolSpec, tipZ: Float, radialOffset d: Float) -> Float? {
        let r = radius(for: tool)
        guard d >= 0, d <= r, r > 0 else { return nil }

        switch tool.kind {
            case .endMill, .drill:
                // Flat-bottomed footprint. A drill's conical point matters
                // for plunge clearance, not for what a 2.5D heightmap shows,
                // so it's modeled the same as a flat end mill here.
                return tipZ

            case .ballNose:
                // Hemisphere: lowest at the centerline (tipZ), rising to
                // tipZ + r at the tool's full radius. `min(d, r)` guards the
                // sqrt against the offset landing a hair past `r` due to
                // float rounding right at the footprint's edge.
                let clamped = min(d, r)
                return tipZ + r - (r * r - clamped * clamped).squareRoot()

            case .vBit, .engraver:
                // Cone: rises linearly from the tip at a rate set by the
                // tool's half-angle. Falls back to a flat disc if no angle
                // is on file, rather than silently mis-shaping the cut —
                // a missing angle should be visible as "looks like an end
                // mill," not a subtly wrong cone.
                guard let includedAngle = tool.tipAngleDegrees, includedAngle > 0, includedAngle < 180 else {
                    return tipZ
                }
                let halfAngleRadians = (includedAngle / 2) * .pi / 180
                let rise = Double(d) / tan(halfAngleRadians)
                return tipZ + Float(rise)
        }
    }
}