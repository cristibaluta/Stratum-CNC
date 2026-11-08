//
//  EdgeMeasure.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.11.2026.
//


import Foundation
import simd
import SwiftSTEP

/// What a selected edge is, and its size, for the selection details. The geometry keeps only the
/// polyline each edge was tessellated into, so the kind is recovered from the points: all on one
/// line, all on one circle, or neither.
extension STEPDisplayGeometry {

    struct EdgeMeasure: Equatable, Sendable {
        enum Kind: Sendable { case line, arc, circle, curve }
        var kind: Kind
        /// Length along the edge, mm.
        var length: Float
        /// Radius of an arc or a circle, mm.
        var radius: Float?
    }

    /// How far (mm) the points may stray from a line or a circle and still count as on it.
    static let measureTolerance: Float = 0.01

    /// One measure per edge of `ids`, in the order the geometry stores them.
    func measures(of ids: Set<STEP.EdgeID>) -> [EdgeMeasure] {
        var result: [EdgeMeasure] = []
        for body in bodies {
            for edge in body.edges where ids.contains(edge.id) {
                var polyline = [body.points[edge.vertices.lowerBound]]
                for index in stride(from: edge.vertices.lowerBound, to: edge.vertices.upperBound, by: 2) {
                    polyline.append(body.points[index + 1])
                }
                result.append(Self.measure(polyline: polyline))
            }
        }
        return result
    }

    static func measure(polyline p: [SIMD3<Float>]) -> EdgeMeasure {
        var length: Float = 0
        for i in p.indices.dropFirst() { length += simd_distance(p[i], p[i - 1]) }
        let tolerance = measureTolerance
        let first = p[0], last = p[p.count - 1]
        let closed = simd_distance(first, last) <= tolerance

        if !closed {
            let direction = simd_normalize(last - first)
            if p.allSatisfy({ simd_length(simd_cross(direction, $0 - first)) <= tolerance }) {
                return EdgeMeasure(kind: .line, length: length, radius: nil)
            }
        }

        // The circle through three well-spread points, then every point checked against it.
        let n = p.count
        let (j, k) = closed ? (n / 3, 2 * n / 3) : (n / 2, n - 1)
        let a = SIMD3<Double>(first) - SIMD3<Double>(p[k])
        let b = SIMD3<Double>(p[j]) - SIMD3<Double>(p[k])
        let normal = simd_cross(a, b)
        let denominator = 2 * simd_length_squared(normal)
        if denominator > 1e-12 {
            let c = SIMD3<Double>(p[k])
            let center = simd_cross(simd_dot(a, a) * b - simd_dot(b, b) * a, normal) / denominator + c
            let radius = simd_length(SIMD3<Double>(first) - center)
            let unit = simd_normalize(normal)
            let slack = max(Double(tolerance), radius * 0.002)
            if radius.isFinite, radius < 1e6,
               p.allSatisfy({
                   let point = SIMD3<Double>($0)
                   return abs(simd_length(point - center) - radius) <= slack && abs(simd_dot(unit, point - c)) <= slack
               }) {
                return EdgeMeasure(kind: closed ? .circle : .arc, length: length, radius: Float(radius))
            }
        }
        return EdgeMeasure(kind: .curve, length: length, radius: nil)
    }
}