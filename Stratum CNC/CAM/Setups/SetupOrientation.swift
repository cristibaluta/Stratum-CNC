//
//  SetupOrientation.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.11.2026.
//

import Foundation

/// A rotation of the stock, to tell whether a setup's results are still valid.
struct SetupOrientation: Hashable, Sendable {
    var angle: Double
    var axis: SetupAxis
}
