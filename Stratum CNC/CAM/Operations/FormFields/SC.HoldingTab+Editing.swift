//
//  SC.HoldingTab+Editing.swift
//  Stratum CNC
//
//  What the holding tabs editor needs on top of the library's `SC.HoldingTab`.
//

import Foundation
import StratumCAM

extension SC.HoldingTab {

    /// The ranges `SC.MachiningOperation.formFields` gives these values.
    static let positionRange: ClosedRange<Double> = 0...1
    static let widthRange: ClosedRange<Double> = 1...20
    static let heightRange: ClosedRange<Double> = 0.1...10

    /// A tab with the library's default size, put in the middle of the largest gap between
    /// the existing ones so they don't pile up at the same spot.
    static func new(after tabs: [SC.HoldingTab]) -> SC.HoldingTab {
        var tab = SC.HoldingTab(positionRatio: 0.5)
        let positions = ([0.0] + tabs.map(\.positionRatio).sorted() + [1.0])
        var best = (gap: 0.0, middle: 0.5)
        for (a, b) in positions.adjacentPairs() where b - a > best.gap {
            best = (b - a, (a + b) / 2)
        }
        tab.positionRatio = best.middle
        return tab
    }
}
