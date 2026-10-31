//
//  ToolShape.swift
//  Stratum CNC
//
//  What the heightmap carve and the canvas need to know about how a tool's tip is
//  shaped, and how tool types are grouped when a G-code header's tool is matched
//  against the tools library.
//

import Foundation

/// How a tool's tip cuts, which is all the heightmap carve and the 3D tool marker care about.
enum ToolShape: Hashable, Sendable {
    /// Flat-bottomed cylinder. A drill's conical point matters for plunge clearance, not for what
    /// a 2.5D heightmap shows, so drills and thread mills are modelled the same way.
    case flat
    /// Hemispherical tip.
    case ball
    /// Cone from the tip up to the full diameter; the half-angle comes from the tool's tip angle.
    case cone
}

extension ToolType {

    /// The tip shape the heightmap carves and the canvas draws for this type.
    var shape: ToolShape {
        switch self {
            case .endMill, .corn, .solderMaskRemover, .drill, .threadMill: .flat
            case .ballNose: .ball
            case .vBit, .chamfer, .engraving: .cone
        }
    }

    /// The type this one counts as when a header's tool is matched against the library: a corn or
    /// solder mask remover bit is an end mill as far as a header can tell, and a chamfer bit is a V-bit.
    /// Not the same as `shape`: an end mill, a drill and a thread mill share a shape but are
    /// different tools.
    var matchingType: ToolType {
        switch self {
            case .corn, .solderMaskRemover: .endMill
            case .chamfer: .vBit
            default: self
        }
    }
}
