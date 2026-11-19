//
//  ToolGeometry.swift
//  Stratum CNC
//
//  The part of a `Tool` the heightmap carve needs: how wide it is and what its tip looks like.
//  A small value of its own, not the `Tool`, so that the carve's cache key (`HeightmapCarveCache.Setup`,
//  compared on every carve request) and the request handed to the background task don't carry or
//  compare a tool's name, link, quantity and presets. Editing those in the library must not throw
//  away a carved surface.
//

import Foundation

struct ToolGeometry: Hashable, Sendable {

    /// Cutting diameter in millimeters.
    let diameter: Double
    let shape: ToolShape
    /// Included (full) tip angle in degrees, for `.cone` tools. `nil` when it doesn't apply or
    /// isn't known; a zero or negative angle counts as not known.
    let tipAngle: Double?

    init(diameter: Double, shape: ToolShape, tipAngle: Double? = nil) {
        self.diameter = diameter
        self.shape = shape
        self.tipAngle = (tipAngle ?? 0) > 0 ? tipAngle : nil
    }
}

extension Tool {

    var geometry: ToolGeometry {
        ToolGeometry(diameter: toolDiameter, shape: type.shape, tipAngle: tipAngle)
    }
}

// MARK: - Drawing

/// The coating a cutter is drawn in: the cutting part takes it, the shank stays bare steel.
enum ToolCoating: Sendable {
    /// Bare carbide, one flat gray; what a tool with nothing to go by is drawn in.
    case carbide
    /// A smooth rainbow sheen along the cutting part, drawn by the shader.
    case rainbow

    /// The flat color of the cutting part. A rainbow is colored by the shader, so this is only
    /// what it falls back to.
    var flatColor: SIMD4<Float> {
        SIMD4<Float>(0.58, 0.60, 0.63, 1)
    }
}

/// How tall and how wide each part of the cutter is drawn on the canvas, from the tip upward:
/// the flutes, then the shank. A small value of its own (like `ToolGeometry`) so the canvas can
/// tell by `==` whether what is drawn changed. The tip shape and the cutting diameter stay in
/// `ToolGeometry`.
struct ToolDrawing: Hashable, Sendable {

    /// Height of the cutting part above the tip, in millimeters.
    let fluteLength: Double
    /// Diameter of the shank, in millimeters.
    let shankDiameter: Double
    /// Tip to the end of the shank, in millimeters.
    let overallLength: Double
    let coating: ToolCoating

    /// What is drawn when a length is missing or not usable.
    static let fallbackFluteLength: Double = 12
    /// Shank drawn above the flutes when the tool's overall length isn't known.
    static let fallbackShankLength: Double = 15

    init(fluteLength: Double?,
         shankDiameter: Double,
         toolDiameter: Double,
         overallLength: Double?,
         coating: ToolCoating) {
        func usable(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value > 0 else {
                return nil
            }
            return value
        }
        let flute = usable(fluteLength) ?? Self.fallbackFluteLength
        self.fluteLength = flute
        // No shank diameter on file: the shank is as wide as the cutting part.
        self.shankDiameter = usable(shankDiameter) ?? max(toolDiameter, 0)
        // An overall length that doesn't clear the flutes tells nothing about the shank.
        if let overall = usable(overallLength), overall > flute {
            self.overallLength = overall
        } else {
            self.overallLength = flute + Self.fallbackShankLength
        }
        self.coating = coating
    }
}

extension Tool {

    /// The flutes, shank and coating the canvas draws for this tool.
    var drawing: ToolDrawing {
        ToolDrawing(fluteLength: cuttingHeight,
                    shankDiameter: shankDiameter,
                    toolDiameter: toolDiameter,
                    overallLength: toolLength,
                    coating: .rainbow)
    }
}
