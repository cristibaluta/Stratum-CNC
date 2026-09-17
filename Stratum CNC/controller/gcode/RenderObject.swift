//
//  RenderObject.swift
//  Stratum CNC
//

import Foundation
import simd

/// How the points in a `RenderObject` should be connected.
/// Mirrors the handful of `MTLPrimitiveType` cases the renderer actually uses,
/// without pulling MetalKit into the model layer.
enum RenderPrimitive {
    case lineStrip  // consecutive points joined into one continuous path
    case lineList   // points consumed in disconnected pairs (start, end, start, end, ...)
}

/// A single drawable "thing" — a toolpath, the stock outline, a position marker, etc.
/// Pure CPU-side data: no `MTLDevice`, no `MTLBuffer`. The model builds these;
/// only `MetalRenderer` knows how to turn them into GPU buffers.
struct RenderObject: Identifiable {
    let id = UUID()
    var points: [SIMD3<Float>]
    var color: SIMD4<Float>
    var primitive: RenderPrimitive = .lineStrip
    var isDashed: Bool = false
    var dashLength: Float = 5.0
}

// MARK: - Common shapes

extension RenderObject {

    /// Wireframe box, e.g. for previewing stock material.
    static func stockBox(minX: Float = 0, maxX: Float = 100,
                          minY: Float = 0, maxY: Float = 50,
                          topZ: Float = 0, bottomZ: Float = -10,
                          color: SIMD4<Float> = SIMD4<Float>(0.6, 0.2, 0.85, 1.0)) -> RenderObject {
        let c000 = SIMD3<Float>(minX, minY, bottomZ)
        let c100 = SIMD3<Float>(maxX, minY, bottomZ)
        let c110 = SIMD3<Float>(maxX, maxY, bottomZ)
        let c010 = SIMD3<Float>(minX, maxY, bottomZ)
        let c001 = SIMD3<Float>(minX, minY, topZ)
        let c101 = SIMD3<Float>(maxX, minY, topZ)
        let c111 = SIMD3<Float>(maxX, maxY, topZ)
        let c011 = SIMD3<Float>(minX, maxY, topZ)

        let points: [SIMD3<Float>] = [
            // Bottom face
            c000, c100, c100, c110, c110, c010, c010, c000,
            // Top face
            c001, c101, c101, c111, c111, c011, c011, c001,
            // Verticals joining the two faces
            c000, c001, c100, c101, c110, c111, c010, c011
        ]

        return RenderObject(points: points, color: color, primitive: .lineList)
    }

    /// Small cylinder marker (e.g. current position, a probe point).
    static func marker(at point: SIMD3<Float>,
                        diameter: Float = 6.0,
                        height: Float = 12.0,
                        segments: Int = 28,
                        strutCount: Int = 4,
                        color: SIMD4<Float> = SIMD4<Float>(1.0, 0.05, 0.05, 1.0)) -> RenderObject {
        let clampedSegments = max(3, segments)
        let radius = max(0, diameter) / 2
        let baseZ = point.z
        let topZ = point.z + height

        func ringPoint(_ i: Int, z: Float) -> SIMD3<Float> {
            let t = Float(i) / Float(clampedSegments)
            let angle = t * 2 * Float.pi
            let x = point.x + radius * cos(angle)
            let y = point.y + radius * sin(angle)
            return SIMD3<Float>(x, y, z)
        }

        var points: [SIMD3<Float>] = []
        points.reserveCapacity(clampedSegments * 4 + max(0, strutCount) * 2)

        for i in 0..<clampedSegments {
            points.append(ringPoint(i, z: baseZ))
            points.append(ringPoint(i + 1, z: baseZ))
        }
        for i in 0..<clampedSegments {
            points.append(ringPoint(i, z: topZ))
            points.append(ringPoint(i + 1, z: topZ))
        }

        let clampedStruts = max(0, strutCount)
        for s in 0..<clampedStruts {
            let i = (s * clampedSegments) / max(1, clampedStruts)
            points.append(ringPoint(i, z: baseZ))
            points.append(ringPoint(i, z: topZ))
        }

        return RenderObject(points: points, color: color, primitive: .lineList)
    }

    /// XYZ axis gizmo at the origin — one `RenderObject` per axis since each
    /// needs its own color (red/green/blue). `RenderObject` doesn't support
    /// per-vertex color changes within a single object, so three thin
    /// objects is simpler than adding that.
    static func axes(length: Float = 50) -> [RenderObject] {
        let origin = SIMD3<Float>(0, 0, 0)
        let x = RenderObject(points: [origin, SIMD3<Float>(length, 0, 0)],
                             color: SIMD4<Float>(1.0, 0.15, 0.15, 1.0),
                             primitive: .lineStrip)
        let y = RenderObject(points: [origin, SIMD3<Float>(0, length, 0)],
                             color: SIMD4<Float>(0.15, 1.0, 0.15, 1.0),
                             primitive: .lineStrip)
        let z = RenderObject(points: [origin, SIMD3<Float>(0, 0, length)],
                             color: SIMD4<Float>(0.15, 0.45, 1.0, 1.0),
                             primitive: .lineStrip)
        return [x, y, z]
    }

    /// Closed dashed polygon — stands in for e.g. a toolpath preview or a
    /// selection outline. Shape/position are arbitrary defaults, not meaningful.
    static func dashedShape(center: SIMD3<Float> = SIMD3<Float>(50, 25, 15),
                            outerRadius: Float = 22,
                            innerRadius: Float = 9,
                            points pointCount: Int = 5,
                            color: SIMD4<Float> = SIMD4<Float>(1.0, 0.75, 0.1, 1.0),
                            dashLength: Float = 3.0) -> RenderObject {
        let spikes = max(3, pointCount)
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(spikes * 2 + 1)

        for i in 0..<(spikes * 2) {
            let angle = Float(i) * .pi / Float(spikes)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            vertices.append(SIMD3<Float>(center.x + radius * cos(angle),
                                         center.y + radius * sin(angle),
                                         center.z))
        }
        vertices.append(vertices[0]) // close the loop

        return RenderObject(points: vertices,
                            color: color,
                            primitive: .lineStrip,
                            isDashed: true,
                            dashLength: dashLength)
    }

    /// The four default items: axes, stock outline, a dashed example shape,
    /// and a position marker — everything `MetalCanvasView` draws out of the box.
    static func defaultScene() -> [RenderObject] {
        axes() + [.stockBox(), .dashedShape(), .marker(at: SIMD3<Float>(50, 25, 0))]
    }
}
