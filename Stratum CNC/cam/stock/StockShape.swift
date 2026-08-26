//
//  StockShape.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

enum StockShape: String, Codable, CaseIterable, Hashable {
    case rectangular
    case round
    case disk

    var displayName: String {
        switch self {
        case .rectangular:
            "Rectangular"
        case .round:
            "Round"
        case .disk:
            "Disk"
        }
    }
}
