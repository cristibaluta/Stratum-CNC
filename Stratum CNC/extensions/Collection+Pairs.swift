//
//  Collection+Pairs.swift
//  Stratum CNC
//

import Foundation

extension Collection {

    /// Consecutive pairs `(0,1), (1,2), …`: replaces `zip(x, x.dropFirst())`.
    func adjacentPairs() -> Zip2Sequence<Self, Self.SubSequence> {
        zip(self, dropFirst())
    }
}

extension Collection where Element == SIMD2<Double> {

    /// Total length of the polyline through the points.
    var pathLength: Double {
        adjacentPairs().reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
}

extension Collection where Element == CGPoint {

    /// Total length of the polyline through the points.
    var pathLength: CGFloat {
        adjacentPairs().reduce(0) { $0 + hypot($1.0.x - $1.1.x, $1.0.y - $1.1.y) }
    }
}
