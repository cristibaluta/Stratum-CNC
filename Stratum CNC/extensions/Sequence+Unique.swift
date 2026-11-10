//
//  Sequence+Unique.swift
//  Stratum CNC
//

import Foundation

extension Sequence where Element: Hashable {

    /// Removes duplicates, keeping first occurrences in order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Sequence where Element: Hashable & Comparable {

    /// Sorted, de-duplicated: replaces `Array(Set(x)).sorted()`.
    func sortedUnique() -> [Element] {
        Array(Set(self)).sorted()
    }
}

extension Sequence {

    /// Removes elements whose `key` was already seen, keeping first occurrences in order.
    func uniqued<Key: Hashable>(by key: (Element) throws -> Key) rethrows -> [Element] {
        var seen = Set<Key>()
        return try filter { try seen.insert(key($0)).inserted }
    }
}
