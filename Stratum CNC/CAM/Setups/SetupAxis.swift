//
//  SetupAxis.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.11.2026.
//

import Foundation

/// The horizontal machine axis a setup turns the stock about.
enum SetupAxis: String, Codable, CaseIterable, Identifiable, Sendable {
    case x
    case y

    var id: String {
        rawValue
    }

    var title: String {
        rawValue.uppercased()
    }
}
