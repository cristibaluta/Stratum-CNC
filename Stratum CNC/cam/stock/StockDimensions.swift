//
//  StockDimensions.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct StockDimensions: Codable, Hashable {
    var width: Double?
    var height: Double?
    var depth: Double?

    var diameter: Double?
    var innerDiameter: Double?
}
