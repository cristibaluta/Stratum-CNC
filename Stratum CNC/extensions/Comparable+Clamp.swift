//
//  Comparable+Clamp.swift
//  Stratum CNC
//

import Foundation

extension Comparable {

    /// `min(max(self, lower), upper)`.
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension BinaryFloatingPoint {

    /// Clamped to `0...1`.
    var clampedToUnit: Self { clamped(to: 0...1) }
}

extension Int {

    /// Clamps a 1-based line number into `1...max(1, lineCount)`.
    func clampedToLine(in lineCount: Int) -> Int {
        clamped(to: 1...Swift.max(1, lineCount))
    }
}
