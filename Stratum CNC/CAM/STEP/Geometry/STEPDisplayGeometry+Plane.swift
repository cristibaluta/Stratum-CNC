//
//  Plane.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.11.2026.
//


import Foundation
import simd
import SwiftSTEP

/// Plane-based edge selection: from some selected edges, find every edge that is connected to
/// them and lies in the same plane. The geometry only has edges (no faces), so the plane is
/// derived from the edges themselves.
extension STEPDisplayGeometry {

    struct Plane: Equatable, Sendable {
        var origin: SIMD3<Float>
        var normal: SIMD3<Float>   // unit length

        func distance(to point: SIMD3<Float>) -> Float {
            abs(simd_dot(normal, point - origin))
        }
    }

    /// How far (mm) a point may sit off a plane and still count as in it, and how far two
    /// endpoints may be apart and still count as the same vertex.
    static let planeTolerance: Float = 0.005
    private static let vertexQuantum: Float = 0.01

    /// The plane all of `edges` lie in, or `nil` if there is no single one.
    ///
    /// Curved or bent edges define it themselves. A single straight edge does not, so it
    /// is taken to lie in the horizontal plane through it (the usual case for a 2.5D part);
    /// a sloped or vertical straight edge alone stays undetermined.
    func plane(containing edges: Set<STEP.EdgeID>) -> Plane? {
        var points: [SIMD3<Float>] = []
        for body in bodies {
            for edge in body.edges where edges.contains(edge.id) {
                points.append(contentsOf: body.points[edge.vertices])
            }
        }
        guard let first = points.first else { return nil }

        // The point farthest from the first one, then the point farthest from that line:
        // a well-conditioned triangle to take the normal from.
        var far = first
        var farthest: Float = 0
        for point in points {
            let d = simd_length_squared(point - first)
            if d > farthest { farthest = d; far = point }
        }
        guard farthest > Self.planeTolerance * Self.planeTolerance else { return nil }
        let direction = simd_normalize(far - first)

        var normal = SIMD3<Float>.zero
        var offLine: Float = 0
        for point in points {
            let cross = simd_cross(direction, point - first)
            let d = simd_length(cross)
            if d > offLine { offLine = d; normal = cross }
        }

        if offLine > Self.planeTolerance {
            normal = simd_normalize(normal)
        } else {
            // All collinear: only a horizontal line has an obvious plane.
            guard abs(direction.z) <= 1e-3 else { return nil }
            normal = SIMD3<Float>(0, 0, 1)
        }

        let plane = Plane(origin: first, normal: normal)
        guard points.allSatisfy({ plane.distance(to: $0) <= Self.planeTolerance }) else { return nil }
        return plane
    }

    /// `start` plus every edge that can be reached from it through shared endpoints, walking
    /// only along edges that lie in `plane`. Stays within each start edge's own body.
    func linkedEdges(startingFrom start: Set<STEP.EdgeID>, in plane: Plane,
                     hiddenBodies: Set<STEP.BodyID> = []) -> Set<STEP.EdgeID> {
        struct Key: Hashable { let x: Int32, y: Int32, z: Int32 }
        func key(_ p: SIMD3<Float>) -> Key {
            Key(x: Int32((p.x / Self.vertexQuantum).rounded()),
                y: Int32((p.y / Self.vertexQuantum).rounded()),
                z: Int32((p.z / Self.vertexQuantum).rounded()))
        }

        var result = start
        for body in bodies where !hiddenBodies.contains(body.id) {
            let seeds = body.edges.indices.filter { start.contains(body.edges[$0].id) }
            guard !seeds.isEmpty else { continue }

            func ends(_ edge: EdgeRange) -> (Key, Key) {
                (key(body.points[edge.vertices.lowerBound]), key(body.points[edge.vertices.upperBound - 1]))
            }

            // Endpoint -> the in-plane edges that start or end there.
            var atVertex: [Key: [Int]] = [:]
            var inPlane = Set<Int>()
            for index in body.edges.indices {
                let edge = body.edges[index]
                guard body.points[edge.vertices].allSatisfy({ plane.distance(to: $0) <= Self.planeTolerance }) else { continue }
                inPlane.insert(index)
                let (a, b) = ends(edge)
                atVertex[a, default: []].append(index)
                if b != a { atVertex[b, default: []].append(index) }
            }

            var visited = Set(seeds)
            var queue = seeds
            while let index = queue.popLast() {
                let (a, b) = ends(body.edges[index])
                for next in (atVertex[a] ?? []) + (atVertex[b] ?? []) where inPlane.contains(next) && visited.insert(next).inserted {
                    queue.append(next)
                }
            }
            for index in visited { result.insert(body.edges[index].id) }
        }
        return result
    }
}