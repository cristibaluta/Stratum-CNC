import Foundation
import simd

/// Render-ready geometry, built off the main actor. Source coordinates remain
/// untouched. The model is placed like a workpiece on the canvas: the bottom-left
/// corner of its bounding box (min X, min Y) sits at x0 y0 and its top (max Z)
/// at z0, so the part extends toward +X, +Y and down to -Z, same as the stock.
/// The shared origin also avoids Float precision loss far from (0,0,0).
struct STEPDisplayGeometry: Sendable {
    struct EdgeRange: Sendable {
        let id: STEPEdgeID
        let vertices: Range<Int>
    }
    struct Body: Sendable {
        let id: STEPBodyID
        let points: [SIMD3<Float>] // disconnected start/end pairs
        let edges: [EdgeRange]
    }
    let origin: SIMD3<Double>
    var bodies: [Body]

    /// Where the part's corner sits in source coordinates: min X, min Y and the top (max Z).
    /// The surface mesh uses the same origin, so triangles and edges stay registered.
    static func displayOrigin(bounds: STEPBounds?) -> SIMD3<Double> {
        guard let bounds else { return .zero }
        return SIMD3<Double>(bounds.min.x, bounds.min.y, bounds.max.z)
    }

    init(model: STEPEdgeModel) throws {
        let origin = Self.displayOrigin(bounds: model.bounds)
        guard (0..<3).allSatisfy({ origin[$0].isFinite }) else {
            throw STEPParseError("Invalid STEP display bounds")
        }
        let grouped = Dictionary(grouping: model.edges, by: { $0.id.bodyID })
        var bodies: [Body] = []
        for body in model.bodies {
            try Task.checkCancellation()
            var points: [SIMD3<Float>] = []
            var ranges: [EdgeRange] = []
            for edge in grouped[body.id] ?? [] {
                try Task.checkCancellation()
                guard edge.points.count >= 2 else { continue }
                let start = points.count
                func displayPoint(_ source: SIMD3<Double>) throws -> SIMD3<Float> {
                    let local = source - origin
                    guard (0..<3).allSatisfy({ local[$0].isFinite && abs(local[$0]) <= 10_000_000 }) else {
                        throw STEPParseError("STEP extent exceeds the supported display range (20 km)")
                    }
                    return SIMD3<Float>(local)
                }
                var previous = try displayPoint(edge.points[0])
                for point in edge.points.dropFirst() {
                    if points.count % 4096 == 0 { try Task.checkCancellation() }
                    let current = try displayPoint(point)
                    points.append(previous)
                    points.append(current)
                    previous = current
                }
                ranges.append(EdgeRange(id: edge.id, vertices: start..<points.count))
            }
            if !points.isEmpty { bodies.append(Body(id: body.id, points: points, edges: ranges)) }
        }
        self.origin = origin
        self.bodies = bodies
    }

    /// Uses exactly the Float points handed to Metal. Coordinates and tolerance
    /// are AppKit view points, not drawable pixels, so Retina does not alter picking.
    func hitTest(at point: CGPoint, viewport: CGSize, matrix: simd_float4x4,
                 hiddenBodies: Set<STEPBodyID> = [], tolerance: CGFloat = 6) -> STEPEdgeID? {
        guard viewport.width > 0, viewport.height > 0, tolerance >= 0 else { return nil }
        var best: (id: STEPEdgeID, distance: Float, depth: Float)?
        let cursor = SIMD2<Float>(Float(point.x), Float(point.y))
        let limit = Float(tolerance * tolerance)
        for body in bodies where !hiddenBodies.contains(body.id) {
            for edge in body.edges {
                for index in stride(from: edge.vertices.lowerBound, to: edge.vertices.upperBound, by: 2) {
                    guard let (a, b) = Self.projectSegment(body.points[index], body.points[index + 1], matrix: matrix, viewport: viewport) else { continue }
                    let delta = SIMD2<Float>(b.x - a.x, b.y - a.y)
                    let offset = cursor - SIMD2<Float>(a.x, a.y)
                    let length = simd_length_squared(delta)
                    let t = length > 1e-12 ? min(1, max(0, simd_dot(offset, delta) / length)) : 0
                    let distance = simd_length_squared(offset - delta * t)
                    guard distance <= limit else { continue }
                    let depth = a.z + (b.z - a.z) * t
                    if let previous = best,
                       distance > previous.distance + 1e-4 || (abs(distance - previous.distance) <= 1e-4 && depth >= previous.depth) {
                        continue
                    }
                    best = (edge.id, distance, depth)
                }
            }
        }
        return best?.id
    }

    /// Homogeneous clipping against Metal's volume: -w...w for XY, 0...w
    /// for Z. Clip before dividing, including segments crossing near/far planes.
    static func projectSegment(_ start: SIMD3<Float>, _ end: SIMD3<Float>, matrix: simd_float4x4,
                               viewport: CGSize) -> (SIMD3<Float>, SIMD3<Float>)? {
        let a = matrix * SIMD4<Float>(start, 1)
        let b = matrix * SIMD4<Float>(end, 1)
        guard (0..<4).allSatisfy({ a[$0].isFinite && b[$0].isFinite }) else { return nil }
        let planesA = [a.w+a.x, a.w-a.x, a.w+a.y, a.w-a.y, a.z, a.w-a.z, a.w-1e-7]
        let planesB = [b.w+b.x, b.w-b.x, b.w+b.y, b.w-b.y, b.z, b.w-b.z, b.w-1e-7]
        var low: Float = 0
        var high: Float = 1
        for i in planesA.indices {
            let f = planesA[i], g = planesB[i]
            if f < 0 && g < 0 { return nil }
            if f < 0 { low = max(low, f / (f - g)) }
            if g < 0 { high = min(high, f / (f - g)) }
            if low > high { return nil }
        }
        func screen(_ t: Float) -> SIMD3<Float> {
            let clip = a + (b - a) * t
            return SIMD3<Float>((clip.x / clip.w + 1) * Float(viewport.width) / 2,
                                (clip.y / clip.w + 1) * Float(viewport.height) / 2,
                                clip.z / clip.w)
        }
        return (screen(low), screen(high))
    }
}

/// A drag that returns to its starting point is still a drag, not a click.
struct CanvasClickTracker {
    private var start: CGPoint?
    private var dragged = false
    mutating func begin(at point: CGPoint) { start = point; dragged = false }
    mutating func move(to point: CGPoint) {
        if let start, hypot(point.x - start.x, point.y - start.y) > 3 { dragged = true }
    }
    mutating func end(at point: CGPoint) -> Bool {
        move(to: point)
        let clicked = start != nil && !dragged
        start = nil
        return clicked
    }
    var isDragging: Bool { dragged }
}
