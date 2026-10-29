//
//  RampType.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import Foundation

enum RampType: String, CaseIterable, Codable, Hashable {
    // The raw values are what saved projects hold, so they stay as they are; `title` is what
    // the app shows.
    case none = "None"
    case linear = "Linear"
    case helix = "Helix"

    var title: String {
        switch self {
            case .none:   return "Plunge"
            case .linear: return "Linear"
            case .helix:  return "Helix"
        }
    }
}

struct RampingSettings: Codable, Hashable {
    var enabled: Bool
    var type: RampType
    var angle: Double
    var length: Double
}
