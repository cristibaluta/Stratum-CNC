//
//  StockLibrary.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct StockLibrary: Codable {
    var schemaVersion: Int
    var stocks: [StockMaterial]

    init(
        schemaVersion: Int = 1,
        stocks: [StockMaterial] = []
    ) {
        self.schemaVersion = schemaVersion
        self.stocks = stocks
    }
}
