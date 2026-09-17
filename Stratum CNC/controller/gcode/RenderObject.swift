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
}
