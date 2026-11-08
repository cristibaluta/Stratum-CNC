//
//  STEPFacePicker.swift
//  Stratum CNC
//
//  Picking a flat face of a shaded STEP model. The geometry only has edges, so a face is found
//  from the surface mesh: the triangle under the cursor, the flat patch of connected coplanar
//  triangles around it, and the outline of that patch (its outer loop and the loops of any
//  holes or islands). The STEP edges that run along that outline are the face's edges.
//
//  Flat faces only. A hole or a round wall is picked through its circle or its edges.
//

import Foundation
import simd
import SwiftSTEP

enum STEPFacePicker {

    /// A flat patch of the surface: its plane and the segments around it.
    struct Region {
        var plane: STEPDisplayGeometry.Plane
        var boundary: [(SIMD3<Float>, SIMD3<Float>)]
    }

    private struct Key: Hashable, Comparable {
        let x: Int32, y: Int32, z: Int32
        static func < (l: Key, r: Key) -> Bool {
            l.x != r.x ? l.x < r.x : (l.y != r.y ? l.y < r.y : l.z < r.z)
        }
    }
    private struct EdgeKey: Hashable { let a: Key, b: Key }

    /// Vertices closer than this are the same vertex (mm).
    private static let quantum: Float = 0.01
    /// How far (mm) a vertex may sit off a plane and still count as in it.
    private static let planeTolerance: Float = 0.01

    private static func key(_ p: SIMD3<Float>) -> Key {
        Key(x: Int32((p.x / quantum).rounded()), y: Int32((p.y / quantum).rounded()), z: Int32((p.z / quantum).rounded()))
    }

    // MARK: - The triangle under the cursor

    /// The nearest triangle under `point` (AppKit view points, like `STEPDisplayGeometry.hitTest`)
    /// and its depth: smaller is nearer.
    static func pickTriangle(positions: [SIMD3<Float>], indices: [Int], at point: CGPoint,
                             viewport: CGSize, matrix: simd_float4x4) -> (triangle: Int, depth: Float)? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        let cursor = SIMD2<Float>(Float(point.x), Float(point.y))
        let half = SIMD2<Float>(Float(viewport.width), Float(viewport.height)) / 2

        // Every vertex on screen once; NaN where it can't be.
        var screen = [SIMD3<Float>](repeating: SIMD3<Float>(repeating: .nan), count: positions.count)
        for i in positions.indices {
            let clip = matrix * SIMD4<Float>(positions[i], 1)
            guard clip.w > 1e-7 else { continue }
            screen[i] = SIMD3<Float>((clip.x / clip.w + 1) * half.x, (clip.y / clip.w + 1) * half.y, clip.z / clip.w)
        }

        var best: (triangle: Int, depth: Float)?
        for t in 0..<(indices.count / 3) {
            let a = screen[indices[3 * t]], b = screen[indices[3 * t + 1]], c = screen[indices[3 * t + 2]]
            guard a.x.isFinite, b.x.isFinite, c.x.isFinite else { continue }
            guard cursor.x >= min(a.x, b.x, c.x), cursor.x <= max(a.x, b.x, c.x),
                  cursor.y >= min(a.y, b.y, c.y), cursor.y <= max(a.y, b.y, c.y) else { continue }

            let v0 = SIMD2<Float>(b.x - a.x, b.y - a.y)
            let v1 = SIMD2<Float>(c.x - a.x, c.y - a.y)
            let v2 = cursor - SIMD2<Float>(a.x, a.y)
            let d = v0.x * v1.y - v1.x * v0.y
            guard abs(d) > 1e-9 else { continue }          // edge-on
            let u = (v2.x * v1.y - v1.x * v2.y) / d
            let v = (v0.x * v2.y - v2.x * v0.y) / d
            let w = 1 - u - v
            guard u >= 0, v >= 0, w >= 0 else { continue }

            let depth = w * a.z + u * b.z + v * c.z
            guard depth >= 0, depth <= 1 else { continue }
            if best == nil || depth < best!.depth { best = (t, depth) }
        }
        return best
    }

    // MARK: - The flat patch around it

    /// The flat face `triangle` is part of: every triangle in its plane that can be reached from
    /// it through shared edges, and the segments that have a triangle of the patch on one side only.
    /// `nil` if that triangle has no area.
    static func flatRegion(positions: [SIMD3<Float>], indices: [Int], triangle: Int) -> Region? {
        func corners(_ t: Int) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
            (positions[indices[3 * t]], positions[indices[3 * t + 1]], positions[indices[3 * t + 2]])
        }
        let (a, b, c) = corners(triangle)
        let cross = simd_cross(b - a, c - a)
        let area = simd_length(cross)
        guard area > 1e-9 else { return nil }
        let plane = STEPDisplayGeometry.Plane(origin: a, normal: cross / area)

        // Triangles in the same plane (either way up) that have an area.
        var edgeToTriangles: [EdgeKey: [Int]] = [:]
        var segments: [EdgeKey: (SIMD3<Float>, SIMD3<Float>)] = [:]
        for t in 0..<(indices.count / 3) {
            let (p, q, r) = corners(t)
            guard plane.distance(to: p) <= planeTolerance,
                  plane.distance(to: q) <= planeTolerance,
                  plane.distance(to: r) <= planeTolerance,
                  simd_length(simd_cross(q - p, r - p)) > 1e-9 else { continue }
            for (u, v) in [(p, q), (q, r), (r, p)] {
                let (ku, kv) = (key(u), key(v))
                guard ku != kv else { continue }
                let edge = EdgeKey(a: min(ku, kv), b: max(ku, kv))
                edgeToTriangles[edge, default: []].append(t)
                segments[edge] = (u, v)
            }
        }

        // The patch connected to the picked triangle.
        var inRegion: Set<Int> = [triangle]
        var queue = [triangle]
        var trianglesAtEdge: [Int: [EdgeKey]] = [:]
        for (edge, triangles) in edgeToTriangles {
            for t in triangles { trianglesAtEdge[t, default: []].append(edge) }
        }
        while let t = queue.popLast() {
            for edge in trianglesAtEdge[t] ?? [] {
                for next in edgeToTriangles[edge] ?? [] where inRegion.insert(next).inserted {
                    queue.append(next)
                }
            }
        }

        // Its outline: the segments only one triangle of the patch has.
        var boundary: [(SIMD3<Float>, SIMD3<Float>)] = []
        for (edge, triangles) in edgeToTriangles where triangles.count == 1 && inRegion.contains(triangles[0]) {
            if let segment = segments[edge] { boundary.append(segment) }
        }
        return boundary.isEmpty ? nil : Region(plane: plane, boundary: boundary)
    }
}

extension STEPDisplayGeometry {

    /// The edges of body `bodyID` that run along the outline of `region`: in its plane, with
    /// every point on the outline. The mesh and the edges are tessellated separately, so "on" has
    /// a tolerance that grows a little with the size of the face.
    func edges(onBoundaryOf region: STEPFacePicker.Region, in bodyID: STEP.BodyID) -> Set<STEP.EdgeID> {
        guard let body = bodies.first(where: { $0.id == bodyID }) else { return [] }

        var low = SIMD3<Float>(repeating: .infinity)
        var high = SIMD3<Float>(repeating: -.infinity)
        for (a, b) in region.boundary {
            low = simd_min(low, simd_min(a, b))
            high = simd_max(high, simd_max(a, b))
        }
        let tolerance = max(0.05, simd_length(high - low) * 0.0015)

        func distance(_ p: SIMD3<Float>, toSegment a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
            let ab = b - a
            let length = simd_length_squared(ab)
            let t = length > 1e-12 ? min(1, max(0, simd_dot(p - a, ab) / length)) : 0
            return simd_distance(p, a + ab * t)
        }

        var result = Set<STEP.EdgeID>()
        for edge in body.edges {
            let points = body.points[edge.vertices]
            guard points.allSatisfy({ region.plane.distance(to: $0) <= tolerance }) else { continue }
            let onOutline = points.allSatisfy { point in
                region.boundary.contains { distance(point, toSegment: $0.0, $0.1) <= tolerance }
            }
            if onOutline { result.insert(edge.id) }
        }
        return result
    }
}
