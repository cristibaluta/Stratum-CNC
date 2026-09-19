//
//  GCodeHeader.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import Foundation
import simd

/// Metadata a CAM package embeds in a comment block at the top of a program
/// — everything the file says about itself that isn't motion. Only tool
/// specs are extracted for now; add more fields here (stock, origin, ...)
/// as the app starts using them.
struct GCodeHeader: Sendable, Equatable {
    /// Tool specs declared by the header, keyed by tool number (the `T` in
    /// `T4 M6`).
    var tools: [Int: ToolSpec] = [:]

    /// XY position of the part relative to the machine origin, in
    /// millimeters, for CAMs that write one. `nil` when the header doesn't
    /// say — as opposed to `(0, 0)`, which it does.
    var xyOffset: SIMD2<Float>? = nil
}

extension ToolSpec {
    /// Most CAM headers don't say how many flutes a tool has, but `ToolSpec`
    /// requires a number. Nothing in the heightmap carve reads it today.
    static let assumedFlutes = 2
}

/// Reads one CAM package's header dialect. `GCodeParser` hands every
/// registered parser the leading comment block of the file, in order, and
/// uses the first one that recognises it — so adding support for another CAM
/// is a new conforming type plus one entry in `GCodeParser.init`.
protocol GCodeHeaderParser {
    /// `headerLines` is the file's leading comment/blank block, without line
    /// endings. Returns `nil` when this isn't a header this parser understands,
    /// so the next parser gets a chance.
    func parse(headerLines: [String]) -> GCodeHeader?
}
