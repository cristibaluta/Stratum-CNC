//
//  HoldingTab.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 11.11.2026.
//

import Foundation
import StratumCAM

extension SC.HoldingTab: Codable {
    /// The `id` only identifies the tab in an editor, so it isn't saved: a decoded tab gets a new one.
    private enum CodingKeys: String, CodingKey {
        case positionRatio, width, height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let positionRatio = try container.decode(Double.self, forKey: .positionRatio)
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        
        self.init(positionRatio: positionRatio, width: width, height: height)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(positionRatio, forKey: .positionRatio)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }
}
