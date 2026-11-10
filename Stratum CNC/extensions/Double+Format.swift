//
//  Double+Format.swift
//  Stratum CNC
//

import Foundation

extension BinaryFloatingPoint {

    /// Fixed decimals: `2.5.fixed(2)` → `"2.50"`.
    func fixed(_ decimals: Int) -> String {
        String(format: "%.\(decimals)f", Double(self))
    }

    /// Up to `maxDecimals` decimals with trailing zeros trimmed:
    /// `2.000` → `"2"`, `-0.500` → `"-0.5"`, `-0.0001` → `"0"`.
    func trimmedString(maxDecimals: Int = 3) -> String {
        var text = fixed(maxDecimals)
        if text.contains(".") {
            while text.hasSuffix("0") {
                text.removeLast()
            }
            if text.hasSuffix(".") {
                text.removeLast()
            }
        }
        return (text == "-0" || text.isEmpty) ? "0" : text
    }

    /// No decimals for whole numbers, otherwise `decimals` places (`6` → `"6"`, `6.35` → `"6.35"`).
    func wholeOrFixed(_ decimals: Int = 2) -> String {
        isWhole ? fixed(0) : fixed(decimals)
    }
}
