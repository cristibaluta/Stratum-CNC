//
//  FloatingPoint+Rounding.swift
//  Stratum CNC
//

import Foundation

extension FloatingPoint {

    /// `true` when there is no fractional part.
    var isWhole: Bool { truncatingRemainder(dividingBy: 1) == 0 }
}

extension BinaryFloatingPoint {

    /// `Int(self.rounded())`.
    var roundedInt: Int { Int(rounded()) }

    /// Fixed-point integer: `Int((self * scale).rounded())`, e.g. `scale: 1000` → thousandths.
    func roundedInt(scale: Double) -> Int {
        Int((self * Self(scale)).rounded())
    }
}

extension Double {

    /// Rounds to a number of decimal places: `(v * 10ⁿ).rounded() / 10ⁿ`.
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }

    /// Rounds to the nearest multiple of `step`.
    func rounded(toMultipleOf step: Double) -> Double {
        (self / step).rounded() * step
    }
}
