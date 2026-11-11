//
//  STEPContourBuilder.swift
//  Stratum CNC
//
/// Turns the sampled edges of a STEP model into the contours the toolpath engine takes:
/// edges are joined end to end, and a chain that comes back to its start is closed.
/// Only X and Y are used, the toolpath's depth comes from its Start Z and End Z.
///
/// The edges are the display polylines (0.01 mm chord tolerance), so arcs and circles
/// reach the engine as many short lines, like curves imported from an SVG.
///
import Foundation
import simd
import StratumCAM
import SwiftSTEP

enum STEPContourBuilder {

    /// Edge ends closer than this (mm) are the same point. Display coordinates are Float.
    static let joinTolerance = 0.005

    static func contours(from polylines: [[SIMD3<Double>]]) -> [SC.Contour] {

        var remaining: [[SIMD2<Double>]] = polylines.compactMap { polyline in
            var points: [SIMD2<Double>] = []
            for point in polyline {
                let flat = point.xy
                if let last = points.last, simd_distance(last, flat) < 1e-9 {
                    continue
                }
                points.append(flat)
            }
            return points.count >= 2 ? points : nil
        }

        var chains: [[SIMD2<Double>]] = []
        
        while !remaining.isEmpty {
            var chain = remaining.removeFirst()
            var extended = true
            while extended, !isClosed(chain) {
                extended = false
                for index in remaining.indices {
                    let other = remaining[index]
                    if near(chain[chain.count - 1], other[0]) {
                        chain.append(contentsOf: other.dropFirst())
                    } else if near(chain[chain.count - 1], other[other.count - 1]) {
                        chain.append(contentsOf: other.reversed().dropFirst())
                    } else if near(chain[0], other[other.count - 1]) {
                        chain = other + chain.dropFirst()
                    } else if near(chain[0], other[0]) {
                        chain = Array(other.reversed()) + chain.dropFirst()
                    } else {
                        continue
                    }
                    remaining.remove(at: index)
                    extended = true
                    break
                }
            }
            chains.append(chain)
        }

        return chains.compactMap { chain in
            var points = chain
            let closed = isClosed(points)
            if closed {
                points[points.count - 1] = points[0]
            }   // no gap left at the seam
            var entities: [SC.Contour.Chained] = []
            for index in 0..<(points.count - 1) where simd_distance(points[index], points[index + 1]) > 1e-9 {
                entities.append(SC.Contour.Chained(geometry: .line(a: points[index], b: points[index + 1]),
                                                   reversed: false))
            }
            return entities.isEmpty ? nil : SC.Contour(entities: entities, isClosed: closed)
        }
    }

    private static func near(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Bool {
        simd_distance(a, b) <= joinTolerance
    }

    /// Comes back to where it started, with more than a single line in between.
    private static func isClosed(_ chain: [SIMD2<Double>]) -> Bool {
        chain.count > 2 && near(chain[0], chain[chain.count - 1])
    }
}
