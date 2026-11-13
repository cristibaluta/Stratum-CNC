//
//  STEPEdgeFingerprint.swift
//  Stratum CNC
//

import Foundation
import simd
import SwiftSTEP

/// What an edge looks like, independent of how the file numbers it. Saved with the toolpath's
/// `STEPEdgeTarget` so the edge can be found again after the model is re-exported.
/// Coordinates are in the file's own frame (mm): a body's `origin` + its local points. That frame
/// does not move when you add material elsewhere, unlike the body-local one.
struct STEPEdgeFingerprint: Codable, Hashable, Sendable {
    /// Arc length, mm.
    var length: Double
    /// Points at 0, 25, 50, 75 and 100 % of the arc length.
    var samples: [SIMD3<Double>]

    static let defaultTolerance = 0.05   // mm

    var isClosed: Bool {
        guard let first = samples.first, let last = samples.last else { return false }
        return length > 0 && simd_distance(first, last) < 1e-3
    }

    /// For a closed edge (a circle…) the middle of its four quarter points; the start point of a
    /// closed edge can move in a re-export, the centre does not.
    var center: SIMD3<Double> {
        samples.prefix(4).reduce(.zero, +) / Double(max(samples.prefix(4).count, 1))
    }

    /// Mean distance of the quarter points from `center`: the radius of a circle.
    var spread: Double {
        let c = center
        let quarter = samples.prefix(4)
        return quarter.map { simd_distance($0, c) }.reduce(0, +) / Double(max(quarter.count, 1))
    }

    /// A point that does not depend on the edge's direction or where a closed edge starts.
    var anchor: SIMD3<Double> {
        isClosed ? center : samples[samples.count / 2]
    }

    /// `points` is how a body stores an edge: start, end, start, end… of consecutive segments.
    init?(segmentPoints points: ArraySlice<SIMD3<Float>>, origin: SIMD3<Double>) {
        guard let first = points.first else { return nil }
        var chain = [SIMD3<Double>(first) + origin]
        var index = points.startIndex
        while index + 1 < points.endIndex {
            chain.append(SIMD3<Double>(points[index + 1]) + origin)
            index += 2
        }
        var cumulative = [0.0]
        for i in 1..<max(chain.count, 1) {
            cumulative.append(cumulative[i - 1] + simd_distance(chain[i - 1], chain[i]))
        }
        let total = cumulative.last ?? 0
        func point(at fraction: Double) -> SIMD3<Double> {
            guard total > 1e-9, chain.count > 1 else { return chain[0] }
            let target = fraction * total
            var i = 1
            while i < chain.count - 1, cumulative[i] < target { i += 1 }
            let span = cumulative[i] - cumulative[i - 1]
            let t = span > 1e-12 ? (target - cumulative[i - 1]) / span : 0
            return chain[i - 1] + (chain[i] - chain[i - 1]) * min(max(t, 0), 1)
        }
        length = total
        samples = [0, 0.25, 0.5, 0.75, 1].map(point(at:))
    }

    /// How far this edge (moved by `shift`) is from `other`, mm; `nil` when they are not the same
    /// edge. Open edges match in either direction.
    func deviation(to other: STEPEdgeFingerprint, shift: SIMD3<Double> = .zero,
                   tolerance tol: Double = defaultTolerance) -> Double? {
        guard isClosed == other.isClosed,
              abs(length - other.length) <= 2 * tol + 1e-4 * max(length, other.length) else { return nil }
        if isClosed {
            let worst = max(simd_distance(center + shift, other.center), abs(spread - other.spread))
            return worst <= tol ? worst : nil
        }
        func worst(_ b: [SIMD3<Double>]) -> Double {
            zip(samples, b).map { simd_distance($0 + shift, $1) }.max() ?? 0
        }
        let best = min(worst(other.samples), worst(Array(other.samples.reversed())))
        return best <= tol ? best : nil
    }
}

extension STEPDocumentScene {

    /// Fingerprints of every edge in the file as it was read (before any turn, scale or move).
    func edgeFingerprints() -> [(id: STEP.EdgeID, print: STEPEdgeFingerprint)] {
        var result: [(id: STEP.EdgeID, print: STEPEdgeFingerprint)] = []
        for body in content.importedGeometry.bodies {
            for edge in body.edges {
                if let print = STEPEdgeFingerprint(segmentPoints: body.points[edge.vertices], origin: body.origin) {
                    result.append((edge.id, print))
                }
            }
        }
        return result
    }

    func edgeFingerprint(of id: STEP.EdgeID) -> STEPEdgeFingerprint? {
        guard let body = content.importedGeometry.bodies.first(where: { $0.id == id.bodyID }),
              let edge = body.edges.first(where: { $0.id == id }) else { return nil }
        return STEPEdgeFingerprint(segmentPoints: body.points[edge.vertices], origin: body.origin)
    }
}

/// Finds, in a re-exported file, the edges a project had picked.
enum STEPEdgeRelinker {
    typealias Entry = (id: STEP.EdgeID, print: STEPEdgeFingerprint)

    /// Old edge id → new edge id, for every wanted edge that has a geometric home.
    /// `wanted` must not repeat an id. Each candidate is given to at most one wanted edge,
    /// best match first, so edges that did not change can't be stolen by look-alikes.
    static func relink(_ wanted: [Entry], among candidates: [Entry],
                       tolerance tol: Double = STEPEdgeFingerprint.defaultTolerance) -> [STEP.EdgeID: STEP.EdgeID] {
        guard !wanted.isEmpty, !candidates.isEmpty else { return [:] }
        let shift = estimateShift(wanted, candidates, tol)

        var pairs: [(w: Int, c: Int, score: Double)] = []
        for (wi, w) in wanted.enumerated() {
            for (ci, c) in candidates.enumerated() {
                if let score = w.print.deviation(to: c.print, shift: shift, tolerance: tol) {
                    pairs.append((wi, ci, score))
                }
            }
        }
        pairs.sort { $0.score < $1.score }

        var result: [STEP.EdgeID: STEP.EdgeID] = [:]
        var usedWanted = Set<Int>(), usedCandidates = Set<Int>()
        for pair in pairs where !usedWanted.contains(pair.w) && !usedCandidates.contains(pair.c) {
            usedWanted.insert(pair.w)
            usedCandidates.insert(pair.c)
            result[wanted[pair.w].id] = candidates[pair.c].id
        }
        return result
    }

    /// The offset between the old and the new file: every old edge votes for the offset to each
    /// edge of the same length; the most voted one wins. Zero wins ties, so an untouched model
    /// is never "shifted".
    private static func estimateShift(_ wanted: [Entry], _ candidates: [Entry], _ tol: Double) -> SIMD3<Double> {
        let cell = tol * 4
        var votes: [SIMD3<Int>: (count: Int, sum: SIMD3<Double>)] = [:]
        for w in wanted {
            for c in candidates where w.print.isClosed == c.print.isClosed
                && abs(w.print.length - c.print.length) <= tol {
                let d = c.print.anchor - w.print.anchor
                let key = SIMD3<Int>(d / cell, rounding: .toNearestOrAwayFromZero)
                let old = votes[key] ?? (0, .zero)
                votes[key] = (old.count + 1, old.sum + d)
            }
        }
        guard let best = votes.max(by: { $0.value.count < $1.value.count }),
              best.value.count > (votes[SIMD3<Int>(0, 0, 0)]?.count ?? 0) else { return .zero }
        return best.value.sum / Double(best.value.count)
    }
}
