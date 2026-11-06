import Foundation
import simd

/// Triangulates a face from its boundary segments in the surface's (u, v) plane, by a
/// sweep along u: every distinct vertex u (plus an optional regular lattice) starts a new
/// slab, each slab is cut by the boundary segments that span it, and the region between
/// every pair of consecutive segments (even-odd, so holes need no special casing) is
/// split into rows and strip-triangulated.
///
/// Why not ear clipping: boundary points of a curved face sit only on its boundary, so
/// triangles between them would cut chords through the part. Here interior points are
/// placed on the true surface (`Sampling.evaluate`) at a spacing chosen from the chord
/// tolerance, and boundary points are only ever interpolated along the boundary's own
/// chords, so a face's edge matches the wireframe and its neighbours exactly.
///
/// Pure value geometry: no file, no units, no UI. Triangles come out counter-clockwise in
/// (u, v). Throws `STEPParseError` for a boundary that is not closed.
enum STEPSlabTriangulator {

    struct Vertex {
        var u: Double
        var v: Double
        var position: SIMD3<Double>
    }

    struct Segment {
        var a: Vertex
        var b: Vertex
    }

    /// How interior points are placed. Planes need none.
    struct Sampling {
        /// Surface point at (u, v), for interior row points.
        var evaluate: (Double, Double) -> SIMD3<Double>
        /// Number of rows between two boundary v values at a given u (at least 1).
        var rows: ((Double, Double, Double) -> Int)?
        /// Extra slab boundaries every `latticeStep` in u, for surfaces curved along u.
        var latticeStep: Double?
    }

    struct Result {
        var vertices: [Vertex] = []
        var triangles: [SIMD3<Int>] = []
    }

    private struct ColumnKey: Hashable {
        let low: Int
        let high: Int
    }

    private struct Cut {
        let index: Int
        let left: Vertex
        let right: Vertex
        let middle: Double
    }

    static let maximumLatticeSlabs = 100_000
    static let maximumRowsPerColumn = 512

    static func triangulate(_ segments: [Segment], sampling: Sampling, triangleLimit: Int) throws -> Result {
        guard !segments.isEmpty else { throw STEPParseError("Face has no boundary") }
        var allU: [Double] = []
        allU.reserveCapacity(segments.count * 2)
        for segment in segments {
            for vertex in [segment.a, segment.b] {
                guard vertex.u.isFinite, vertex.v.isFinite,
                      (0..<3).allSatisfy({ vertex.position[$0].isFinite }) else {
                    throw STEPParseError("Face boundary has nonfinite coordinates")
                }
                allU.append(vertex.u)
            }
        }
        guard let minU = allU.min(), let maxU = allU.max(), maxU > minU else {
            throw STEPParseError("Face has a degenerate parameter domain")
        }
        let epsilon = 1e-9 * max(1, maxU - minU)
        let representatives = Self.representatives(of: allU, epsilon: epsilon)

        // Left-to-right segments on the snapped u grid; vertical ones bound nothing.
        var edges: [Segment] = []
        edges.reserveCapacity(segments.count)
        for segment in segments {
            var a = segment.a
            var b = segment.b
            a.u = snap(a.u, to: representatives)
            b.u = snap(b.u, to: representatives)
            if a.u == b.u { continue }
            edges.append(a.u < b.u ? Segment(a: a, b: b) : Segment(a: b, b: a))
        }
        guard !edges.isEmpty else { throw STEPParseError("Face boundary is vertical in parameter space") }
        edges.sort { $0.a.u < $1.a.u }

        var breaks = representatives
        if let step = sampling.latticeStep, step > 0, step.isFinite {
            let low = representatives[0]
            let high = representatives[representatives.count - 1]
            let count = Int(((high - low) / step).rounded(.down))
            guard count <= maximumLatticeSlabs else { throw STEPParseError("Face needs too many subdivisions") }
            if count >= 1 {
                for k in 1...count {
                    let u = low + Double(k) * step
                    if u < high - epsilon, abs(snap(u, to: representatives) - u) > epsilon { breaks.append(u) }
                }
                breaks.sort()
            }
        }

        var result = Result()
        var active: [Int] = []
        var next = 0
        var previousRight: [ColumnKey: [Int]] = [:]
        for k in 0..<(breaks.count - 1) {
            if k & 127 == 0 { try Task.checkCancellation() }
            let leftU = breaks[k]
            let rightU = breaks[k + 1]
            while next < edges.count, edges[next].a.u <= leftU {
                active.append(next)
                next += 1
            }
            active.removeAll { edges[$0].b.u <= leftU }
            if active.isEmpty {
                previousRight = [:]
                continue
            }
            guard active.count % 2 == 0 else {
                throw STEPParseError("Face boundary is not closed")
            }
            var cuts: [Cut] = active.map { index in
                let left = point(on: edges[index], at: leftU)
                let right = point(on: edges[index], at: rightU)
                return Cut(index: index, left: left, right: right, middle: (left.v + right.v) / 2)
            }
            cuts.sort { $0.middle != $1.middle ? $0.middle < $1.middle : $0.index < $1.index }

            var newRight: [ColumnKey: [Int]] = [:]
            var i = 0
            while i < cuts.count {
                let low = cuts[i]
                let high = cuts[i + 1]
                let key = ColumnKey(low: low.index, high: high.index)
                // The same pair of segments continues across the shared line: reuse its column.
                let leftColumn = previousRight[key]
                    ?? column(&result, u: leftU, low: low.left, high: high.left, sampling: sampling)
                let rightColumn = column(&result, u: rightU, low: low.right, high: high.right, sampling: sampling)
                newRight[key] = rightColumn
                try strip(&result, leftColumn, rightColumn, triangleLimit: triangleLimit)
                i += 2
            }
            previousRight = newRight
        }
        return result
    }

    // MARK: Helpers

    private static func representatives(of values: [Double], epsilon: Double) -> [Double] {
        var result: [Double] = []
        for value in values.sorted() {
            if let last = result.last, value - last <= epsilon { continue }
            result.append(value)
        }
        return result
    }

    /// Nearest representative (they are sorted and never empty).
    private static func snap(_ value: Double, to representatives: [Double]) -> Double {
        var low = 0
        var high = representatives.count
        while low < high {
            let middle = (low + high) / 2
            if representatives[middle] < value { low = middle + 1 } else { high = middle }
        }
        var best = representatives[min(low, representatives.count - 1)]
        if low > 0, abs(representatives[low - 1] - value) < abs(best - value) {
            best = representatives[low - 1]
        }
        return best
    }

    /// Exact at the segment's ends, so the same boundary vertex is bit-identical on both slabs.
    private static func point(on segment: Segment, at u: Double) -> Vertex {
        if u == segment.a.u { return segment.a }
        if u == segment.b.u { return segment.b }
        let t = (u - segment.a.u) / (segment.b.u - segment.a.u)
        return Vertex(u: u,
                      v: segment.a.v + (segment.b.v - segment.a.v) * t,
                      position: segment.a.position + (segment.b.position - segment.a.position) * t)
    }

    /// Points from `low` to `high` along one line of constant u: the two boundary points,
    /// plus surface points between them when the surface is curved along v.
    private static func column(_ result: inout Result, u: Double, low: Vertex, high: Vertex,
                               sampling: Sampling) -> [Int] {
        let rows = min(maximumRowsPerColumn, max(1, sampling.rows?(u, low.v, high.v) ?? 1))
        var indices: [Int] = []
        indices.reserveCapacity(rows + 1)
        indices.append(result.vertices.count)
        result.vertices.append(low)
        if rows > 1 {
            for j in 1..<rows {
                let v = low.v + (high.v - low.v) * Double(j) / Double(rows)
                indices.append(result.vertices.count)
                result.vertices.append(Vertex(u: u, v: v, position: sampling.evaluate(u, v)))
            }
        }
        indices.append(result.vertices.count)
        result.vertices.append(high)
        return indices
    }

    /// Zips two columns (left, right) into triangles, advancing whichever is behind.
    private static func strip(_ result: inout Result, _ a: [Int], _ b: [Int], triangleLimit: Int) throws {
        let m = a.count - 1
        let n = b.count - 1
        var i = 0
        var j = 0
        while i < m || j < n {
            let advanceLeft = j == n || (i < m && (i + 1) * n <= (j + 1) * m)
            let triangle: SIMD3<Int>
            if advanceLeft {
                triangle = SIMD3<Int>(a[i], b[j], a[i + 1])
                i += 1
            } else {
                triangle = SIMD3<Int>(a[i], b[j], b[j + 1])
                j += 1
            }
            let p0 = result.vertices[triangle.x].position
            let p1 = result.vertices[triangle.y].position
            let p2 = result.vertices[triangle.z].position
            // Collapsed triangles (poles, coincident corners) add nothing.
            guard simd_length_squared(simd_cross(p1 - p0, p2 - p0)) > 1e-36 else { continue }
            result.triangles.append(triangle)
            guard result.triangles.count <= triangleLimit else {
                throw STEPParseError("Triangle limit exceeded")
            }
        }
    }
}
