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
        if let rpm = preset.spindleRPM { spindleRPM = rpm }
        if let feed = preset.feedRate { feedRate = feed }
        if let plunge = preset.plungeFeedRate { plungeRate = plunge }
//        if let depth = preset.depthOfCut { stepDown = depth }
        if let depth = preset.depthOfCut {
            stepDown = depth
            markEdited(.stepDown)
        }
        if let angle = preset.rampAngle { ramping.angle = angle }
    }
}
