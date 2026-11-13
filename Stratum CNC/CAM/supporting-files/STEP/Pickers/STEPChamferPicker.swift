//
//  STEPChamferPicker.swift
//  Stratum CNC
//
//  Picking a chamfer. A chamfer face is not a flat patch when it goes round a hole or a boss
//  (it is a cone), so the flat-face picker finds nothing there. Here the face is the set of
//  connected triangles whose shading normals continue into each other, which holds for a plane
//  and for a cone alike. A chamfer is such a face that is tilted and whose boundary has horizontal
//  edges at two heights: the two rails. Those are what gets selected.
//
//  The mesh may be tessellated in any way: smooth or flat shading, coarse or fine, and its faces
//  need not share vertices along the rails (`STEPDisplayGeometry.edges(onBoundaryOf:)` allows for the
//  chords of a curve lying off it).
//
//  The toolpath does not cut the rails, it cuts the sharp edge the chamfer replaced (see
//  `STEPWorkspace.contours(for:frame:sharpEdgeOfChamfer:)`).
//

import Foundation
import simd
import SwiftSTEP

enum STEPChamferPicker {

    private struct Key: Hashable, Comparable {
        let x: Int32, y: Int32, z: Int32
        static func < (l: Key, r: Key) -> Bool {
            l.x != r.x ? l.x < r.x : (l.y != r.y ? l.y < r.y : l.z < r.z)
        }
    }
    private struct EdgeKey: Hashable { let a: Key, b: Key }

    /// Vertices closer than this are the same vertex (mm).
    private static let quantum: Float = 0.01
    /// Edges whose ends differ in height by less than this are horizontal (mm).
    private static let levelTolerance: Float = 0.01
    /// A chamfer face looks up and is tilted between about 10° and 80° from horizontal:
    /// the vertical component of its normal is between these.
    private static let normalZRange: ClosedRange<Float> = 0.17...0.985
    /// A chamfer is not taller than this (mm); a taller sloped face is a ramp or a draft.
    private static let maxHeight: Float = 8
    /// The most distinct heights of horizontal boundary edges a chamfer may have. Two is the plain
    /// chamfer. A chamfer whose lower edge steps (two cones of a slightly different depth that
    /// continue into each other, or a hole whose wall has a small step) has three: the upper rail
    /// and a lower one at each depth.
    private static let maxHeights = 4
    /// Faces with more triangles than this are not chamfers.
    private static let maxTriangles = 60_000
    /// Normals closer than this (cosine, about 6°) continue into each other. Loose on purpose:
    /// along the seam of a cone the two sides' normals can differ by half a tessellation step,
    /// and a chamfer meets its neighbours at far more than this.
    private static let sameNormal: Float = 0.995
    /// A mesh whose triangles have flat shading (each vertex normal is its triangle's normal) has
    /// no normals that "continue": a cone is a strip of flat facets, each tilted a little against
    /// the next. Such triangles are judged by their geometry instead: neighbours within this angle
    /// (cosine, 25°) of each other, and still tilted like a chamfer, are the same face.
    private static let facetContinuity: Float = 0.9063
    /// The three vertex normals of a triangle closer than this (cosine) to each other: flat shading.
    private static let flatShading: Float = 0.9995

    private static func log(_ message: String) {
        PerfLog.log("pick", "chamfer: \(message)")
    }

    private static func key(_ p: SIMD3<Float>) -> Key {
        Key(x: Int32((p.x / quantum).rounded()), y: Int32((p.y / quantum).rounded()), z: Int32((p.z / quantum).rounded()))
    }

    /// The two rails of the chamfer `triangle` is part of, as regions for
    /// `STEPDisplayGeometry.edges(onBoundaryOf:in:)`: the horizontal boundary edges at the top and
    /// at the bottom of the face. `nil` when the face is not a chamfer: not tilted enough, not
    /// bounded by horizontal edges at two heights, or one that fills a corner (a concave edge,
    /// where the face meets a floor instead of a wall) which a V-bit cannot cut from above.
    /// - Parameter normals: the shading normal of each vertex, in the same space as `positions`.
    static func rails(positions: [SIMD3<Float>], indices: [Int], normals: [SIMD3<Float>],
                      triangle: Int) -> [STEPFacePicker.Region]? {
        let count = indices.count / 3
        guard triangle >= 0, triangle < count, normals.count == positions.count else {
            log("rejected: triangle \(triangle) of \(count), \(normals.count) normals for \(positions.count) vertices")
            return nil
        }

        func corner(_ t: Int, _ i: Int) -> SIMD3<Float> { positions[indices[3 * t + i]] }
        func faceNormal(_ t: Int) -> SIMD3<Float> {
            let sum = (0..<3).reduce(SIMD3<Float>.zero) { $0 + normals[indices[3 * t + $1]] }
            return simd_length(sum) > 1e-6 ? simd_normalize(sum) : .zero
        }
        // Either way up: whether the mesh normals point out of the solid or into it is not relied on.
        // That the face is convex, with a wall below it, is checked from the geometry further down.
        let tilt = faceNormal(triangle).z
        guard normalZRange.contains(abs(tilt)) else {
            log("rejected: normal z \(tilt), a chamfer's is within ±\(normalZRange.lowerBound)…\(normalZRange.upperBound)")
            return nil
        }

        // Triangles by the edges they share.
        var neighbors: [EdgeKey: [Int]] = [:]
        var keys: [[Key]] = []
        keys.reserveCapacity(count)
        for t in 0..<count {
            let k = (0..<3).map { key(corner(t, $0)) }
            keys.append(k)
            for i in 0..<3 {
                let (ku, kv) = (k[i], k[(i + 1) % 3])
                guard ku != kv else { continue }
                neighbors[EdgeKey(a: min(ku, kv), b: max(ku, kv)), default: []].append(t)
            }
        }

        func normal(of t: Int, at k: Key) -> SIMD3<Float>? {
            for i in 0..<3 where keys[t][i] == k {
                let n = normals[indices[3 * t + i]]
                return simd_length(n) > 1e-6 ? simd_normalize(n) : nil
            }
            return nil
        }

        func geometricNormal(_ t: Int) -> SIMD3<Float> {
            let cross = simd_cross(corner(t, 1) - corner(t, 0), corner(t, 2) - corner(t, 0))
            let length = simd_length(cross)
            return length > 1e-12 ? cross / length : .zero
        }
        func isFlatShaded(_ t: Int) -> Bool {
            let n = (0..<3).map { normals[indices[3 * t + $0]] }
            guard n.allSatisfy({ simd_length($0) > 1e-6 }) else { return false }
            let first = simd_normalize(n[0])
            return simd_dot(first, simd_normalize(n[1])) > flatShading && simd_dot(first, simd_normalize(n[2])) > flatShading
        }
        /// `next` continues the face `t` is part of, across their shared edge `ku`-`kv`.
        func continues(_ t: Int, into next: Int, _ ku: Key, _ kv: Key) -> Bool {
            if let a1 = normal(of: t, at: ku), let b1 = normal(of: next, at: ku),
               let a2 = normal(of: t, at: kv), let b2 = normal(of: next, at: kv),
               simd_dot(a1, b1) > sameNormal, simd_dot(a2, b2) > sameNormal {
                return true
            }
            guard isFlatShaded(t), isFlatShaded(next) else {
                return false
            }
            return abs(simd_dot(geometricNormal(t), geometricNormal(next))) > facetContinuity
                && normalZRange.contains(abs(geometricNormal(next).z))
        }

        // The face: neighbours that continue it across the shared edge.
        var face: Set<Int> = [triangle]
        var queue = [triangle]
        while let t = queue.popLast() {
            for i in 0..<3 {
                let (ku, kv) = (keys[t][i], keys[t][(i + 1) % 3])
                guard ku != kv else { continue }
                for next in neighbors[EdgeKey(a: min(ku, kv), b: max(ku, kv))] ?? []
                where next != t && !face.contains(next) {
                    guard continues(t, into: next, ku, kv) else { continue }
                    face.insert(next)
                    queue.append(next)
                }
            }
            if face.count > maxTriangles {
                log("rejected: more than \(maxTriangles) triangles in the face")
                return nil
            }
        }
        log("face: \(face.count) triangle(s), normal z \(tilt)")

        // Its boundary: edges only one triangle of the face has. The horizontal ones are rails.
        struct Segment {
            let a: SIMD3<Float>, b: SIMD3<Float>
            let edge: EdgeKey
            let triangle: Int
            var level: Float { (a.z + b.z) / 2 }
        }
        var rails: [Segment] = []
        var sloped = 0
        for t in face {
            for i in 0..<3 {
                let (ku, kv) = (keys[t][i], keys[t][(i + 1) % 3])
                guard ku != kv else { continue }
                let edge = EdgeKey(a: min(ku, kv), b: max(ku, kv))
                guard (neighbors[edge] ?? []).filter({ face.contains($0) }).count == 1 else { continue }
                let (p, q) = (corner(t, i), corner(t, (i + 1) % 3))
                if abs(p.z - q.z) <= levelTolerance {
                    rails.append(Segment(a: p, b: q, edge: edge, triangle: t))
                } else {
                    sloped += 1
                }
            }
        }

        // Two heights, or a few more when the lower edge steps (`maxHeights`).
        let levels = rails.map(\.level).sorted()
        var groups: [[Float]] = []
        for level in levels {
            if let last = groups.last?.last, level - last <= 2 * levelTolerance {
                groups[groups.count - 1].append(level)
            } else {
                groups.append([level])
            }
        }
        log("boundary: \(rails.count) horizontal segment(s) at \(groups.count) height(s): "
            + groups.map { String(format: "%.3f…%.3f", $0.first ?? 0, $0.last ?? 0) + " (\($0.count))" }.joined(separator: ", "))
        log("boundary: \(sloped) sloped segment(s) besides")
        guard groups.count >= 2, groups.count <= maxHeights, let low = groups.first?.first, let high = groups.last?.last,
              high - low > 2 * levelTolerance, high - low <= maxHeight else {
            log("rejected: a chamfer has horizontal edges at two heights (up to \(maxHeights)), at most \(maxHeight) mm apart")
            return nil
        }
        // Upper and lower rails are told apart the way `STEPDisplayGeometry.chamferRails` does later:
        // by the middle of the highest and the lowest edge.
        let lower = rails.filter { $0.level < (low + high) / 2 }
        let upper = rails.filter { $0.level >= (low + high) / 2 }
        guard !lower.isEmpty, !upper.isEmpty else {
            log("rejected: no edges in the upper or the lower rail")
            return nil
        }

        // A chamfer on a convex edge has a wall going down from its lower rail. One that fills a
        // corner has the floor there, level with the rail.
        var down = 0, level = 0
        for segment in lower {
            for next in neighbors[segment.edge] ?? [] where !face.contains(next) {
                let third = (0..<3).map { corner(next, $0) }.first { p in
                    let k = key(p)
                    return k != segment.edge.a && k != segment.edge.b
                }
                guard let third else { continue }
                if third.z < segment.level - levelTolerance {
                    down += 1
                } else if abs(third.z - segment.level) <= levelTolerance {
                    level += 1
                }
            }
        }
        log("below the lower rail: \(down) triangle(s) going down, \(level) level with it")
        // Nothing found on the other side of the rail at all (0 and 0): the faces are tessellated
        // separately and their meshes don't meet along the rail, so there is nothing to tell a wall
        // from a floor by. That is not a reason to reject; only a floor level with the rail is.
        guard down > level || (down == 0 && level == 0) else {
            log("rejected: no wall below the lower rail, this one fills a corner")
            return nil
        }

        func region(_ segments: [Segment], at z: Float) -> STEPFacePicker.Region {
            STEPFacePicker.Region(plane: STEPDisplayGeometry.Plane(origin: SIMD3<Float>(0, 0, z),
                                                                   normal: SIMD3<Float>(0, 0, 1)),
                                  boundary: segments.map { ($0.a, $0.b) })
        }
        // One region per height: each is matched in its own plane (a lower rail with a step is
        // two or more STEP edges at different heights)
        return groups.compactMap { group -> STEPFacePicker.Region? in
            guard let first = group.first, let last = group.last else { return nil }
            let segments = rails.filter { $0.level >= first - levelTolerance && $0.level <= last + levelTolerance }
            guard !segments.isEmpty else { return nil }
            return region(segments, at: segments.reduce(0) { $0 + $1.level } / Float(segments.count))
        }
    }
}
