//
//  Collection+Safe.swift
//  Stratum CNC
//

import Foundation

extension Collection {

    /// Bounds-checked access: `nil` instead of a crash.
    /// Replaces `guard items.indices.contains(i) else { … }; items[i]`.
    subscript(safe index: Index) -> Element? {
        index >= startIndex && index < endIndex ? self[index] : nil
    }
}
