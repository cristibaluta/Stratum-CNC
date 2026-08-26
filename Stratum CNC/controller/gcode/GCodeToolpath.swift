//
//  GCodeToolpath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation

struct GCodeToolpath: Identifiable, Hashable {
    let id = UUID()
    let toolNumber: Int?
    let operation: String
    let startLine: Int
    let endLine: Int
    let motionCount: Int

    var lineRangeText: String {
        startLine == endLine ? "line \(startLine)" : "lines \(startLine)–\(endLine)"
    }
}
