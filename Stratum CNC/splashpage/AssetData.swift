//
//  AssetData.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 01/09/2026.
//

import Foundation

struct AssetTransform: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
}

struct AssetData: Codable, Hashable {
    let name: String
    // Transformations relative to the original position
    var transform: AssetTransform?
    // One archive can produce several canvas objects, each with its own identity.
    var objects: [AssetObjectData]? = nil
    /// STEP sources are reparsed on reopen; viewer selection is session-only.
    var stepImportID: UUID? = nil
    /// Where a STEP model sits on the canvas: x, y and z in mm.
    var stepOffset: [Double]? = nil
    /// What was done to each body of a STEP file (moved, turned, scaled, deleted), by `STEP.BodyID.stateKey`.
    var stepBodies: [String: STEPBodyState]? = nil
    /// Which face of a STEP file as a whole faced up, in projects saved before its bodies were separate
    /// objects. `nil` is the top, as imported. Read, no longer written: see `stepBodies`.
    var stepOrientation: SetupFace? = nil
}

struct AssetObjectData: Codable, Hashable {
    let id: UUID
    let name: String
    var transform: AssetTransform
}
