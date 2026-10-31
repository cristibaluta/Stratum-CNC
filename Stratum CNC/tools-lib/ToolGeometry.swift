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
