//
//  String+Trim.swift
//  Stratum CNC
//

import Foundation

extension StringProtocol {

    /// Whitespace and newlines removed from both ends.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Empty or whitespace only.
    var isBlank: Bool { trimmed.isEmpty }

    /// Trimmed text, or `nil` when blank.
    var nilIfBlank: String? {
        let text = trimmed
        return text.isEmpty ? nil : text
    }
}
