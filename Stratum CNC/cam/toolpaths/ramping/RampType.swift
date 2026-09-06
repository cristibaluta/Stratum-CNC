//
//  RampType.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import Foundation

enum RampType: String, CaseIterable, Codable, Hashable {
    case none = "None"
    case linear = "Linear"
    case helix = "Helix"
}

struct RampingSettings: Codable, Hashable {
    var enabled: Bool
    var type: RampType
    var angle: Double
    var length: Double
}
