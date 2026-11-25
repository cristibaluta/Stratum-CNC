//
//  Tool+Preset.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 14.10.2026.
//

import Foundation

extension ToolpathData {

    /// Copies the preset's cutting values into the toolpath. Values the preset doesn't
    /// have are left as they are.
    mutating func apply(_ preset: ToolPreset) {
        if let rpm = preset.spindleRPM {
            spindleRPM = rpm
        }
        if let feed = preset.feedRate {
            feedRate = feed
        }
        if let plunge = preset.plungeFeedRate {
            plungeRate = plunge
        }
        if let depth = preset.depthOfCut {
            stepDown = depth
        }
        if let angle = preset.rampAngle {
            ramping.angle = angle
        }
    }
}

/// Where a toolpath's cutting values are not the ones of its tool's preset.
struct ToolpathPresetMismatch {
    let presetName: String
    /// The values that differ, named for the user: "feed rate", "stepdown"…
    let fields: [String]

    var message: String {
        "These values differ from the \u{201C}\(presetName)\u{201D} preset: \(fields.joined(separator: ", "))."
    }
}

extension ToolpathData {

    /// Compares the values `apply(_:)` copies with the tool's preset for `stock`. `nil` when the
    /// tool has no preset for it or every value the preset has is the toolpath's. Nothing is
    /// stored for this, so editing a value back to the preset's makes the difference go away.
    func presetMismatch(for stock: StockMaterialType) -> ToolpathPresetMismatch? {
        guard let preset = tool.preset(for: stock) else {
            return nil
        }
        func differs(_ a: Double, _ b: Double?) -> Bool {
            b.map { abs(a - $0) > 1e-6 } ?? false
        }

        var fields: [String] = []
        if let rpm = preset.spindleRPM, rpm != spindleRPM {
            fields.append("spindle speed")
        }
        if differs(feedRate, preset.feedRate) {
            fields.append("feed rate")
        }
        if differs(plungeRate, preset.plungeFeedRate) {
            fields.append("entry feed")
        }
        if machiningOperation.requirements.usesStepdown, differs(stepDown, preset.depthOfCut) {
            fields.append("stepdown")
        }
        if ramping.enabled, ramping.type != .none, differs(ramping.angle, preset.rampAngle) {
            fields.append("entry angle")
        }
        return fields.isEmpty ? nil : ToolpathPresetMismatch(presetName: preset.name, fields: fields)
    }
}
