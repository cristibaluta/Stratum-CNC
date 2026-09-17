//
//  GCodeModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
class GCodeStore: ObservableObject {

    @Published var document = NCFileDocument()

    @Published var selectedToolpathID: UUID?
    @Published var requestedLine: Int?
    @Published var analyzedLineCount = -1

    var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText]
        for ext in ["nc", "ngc", "gcode", "cnc", "tap"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    func generateGCode(for toolpath: ToolpathData, canvasState: D2_CanvasState) {
        do {
            let gcode = try ToolpathGCodeBuilder.generate(for: toolpath, canvasState: canvasState)
            document.load(from: gcode)
        } catch {
            print("G-code generation failed: \(error.localizedDescription)")
            // consider surfacing this in the UI, e.g. an @Published var lastError: String?
        }
    }

    

    func renderBatch(forPoints points: [SIMD3<Float>],
                     color: SIMD4<Float>,
                     isDashed: Bool = false,
                     dashLength: Float = 5.0) -> RenderBatch? {
        let vertices = buildVertices(points: points, color: color, zOffset: 0.0)
        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(bytes: vertices,
                                             length: vertices.count * MemoryLayout<RenderVertex>.stride,
                                             options: .storageModeShared) else {
            return nil
        }
        return RenderBatch(vertexBuffer: buffer,
                           vertexCount: vertices.count,
                           primitiveType: .lineStrip,
                           isDashed: isDashed,
                           dashLength: dashLength)
    }

    static func markerCylinderVertices(at point: SIMD3<Float>,
                                       diameter: Float = 2.0,
                                       height: Float = 4.0,
                                       segments: Int = 28,
                                       strutCount: Int = 4,
                                       color: SIMD4<Float> = SIMD4<Float>(1.0, 0.05, 0.05, 1.0)) -> [RenderVertex] {
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

        var vertices: [RenderVertex] = []
        vertices.reserveCapacity(clampedSegments * 4 + max(0, strutCount) * 2)

        // Base and top rings, each as `.line` segment pairs (i -> i+1) rather than
        // a closed strip, so both rings can share one buffer with the struts below.
        for i in 0..<clampedSegments {
            vertices.append(RenderVertex(position: ringPoint(i, z: baseZ), color: color, dist: 0))
            vertices.append(RenderVertex(position: ringPoint(i + 1, z: baseZ), color: color, dist: 0))
        }
        for i in 0..<clampedSegments {
            vertices.append(RenderVertex(position: ringPoint(i, z: topZ), color: color, dist: 0))
            vertices.append(RenderVertex(position: ringPoint(i + 1, z: topZ), color: color, dist: 0))
        }

        // Vertical struts connecting the two rings, evenly spaced around the
        // circumference, so the shape reads as a cylinder rather than two
        // unconnected rings floating at different heights.
        let clampedStruts = max(0, strutCount)
        for s in 0..<clampedStruts {
            let i = (s * clampedSegments) / max(1, clampedStruts)
            vertices.append(RenderVertex(position: ringPoint(i, z: baseZ), color: color, dist: 0))
            vertices.append(RenderVertex(position: ringPoint(i, z: topZ), color: color, dist: 0))
        }

        return vertices
    }

    /// Builds the marker `RenderBatch` for a given point -- thin wrapper around
    /// `markerCylinderVertices(at:diameter:height:segments:strutCount:color:)` that
    /// turns the vertices into a GPU buffer the same way `renderBatch(forPoints:...)`
    /// does above. Kept as an instance method (not `static`) only because it needs
    /// `device` for the buffer, same split as `pointsPrefix`/`renderBatch` above.
    func markerBatch(at point: SIMD3<Float>,
                     diameter: Float = 6.0,
                     height: Float = 12.0,
                     segments: Int = 28,
                     strutCount: Int = 4,
                     color: SIMD4<Float> = SIMD4<Float>(1.0, 0.05, 0.05, 1.0)) -> RenderBatch? {
        let vertices = Self.markerCylinderVertices(at: point,
                                                   diameter: diameter,
                                                   height: height,
                                                   segments: segments,
                                                   strutCount: strutCount,
                                                   color: color)
        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(bytes: vertices,
                                             length: vertices.count * MemoryLayout<RenderVertex>.stride,
                                             options: .storageModeShared) else {
            return nil
        }
        return RenderBatch(vertexBuffer: buffer,
                           vertexCount: vertices.count,
                           primitiveType: .line)
    }

    /// `buildWaypoints`/toolpath passes only carry the *endpoints* of each move (plus a
    /// center + direction for arcs) since that's all a real controller needs for `G02`/`G03`.
    /// For the on-screen preview we need actual curvature, so this walks the waypoints and,
    /// for any `arcCW`/`arcCCW` motion, inserts interpolated points along the true arc between
    /// the previous waypoint and this one instead of drawing a straight chord between them.
    /// Internal rather than `private` so a subclass in another file (e.g.
    /// `DemoSlotting`'s boundary-recognition demos, which need to build a
    /// combined result from two different contours -- the physical boundary for
    /// the blue reference, a derived centerline for the yellow toolpath -- rather
    /// than the single shared contour `run(contour:...)` assumes) can tessellate
    /// its own waypoints the same way `run(contours:...)`/`run(facing:)` do,
    /// without duplicating this arc-interpolation logic a third time.
    func tessellateForRender(_ waypoints: [SC.Waypoint], segmentsPerArc: Int = 32) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        var previous: SC.Waypoint?

        for wp in waypoints {
            switch wp.motion {
                case .rapid, .linear:
                    points.append(SIMD3<Float>(Float(wp.position.x), Float(wp.position.y), Float(wp.position.z)))

                case .arcCW(let center), .arcCCW(let center):
                    guard let prev = previous else {
                        points.append(SIMD3<Float>(Float(wp.position.x), Float(wp.position.y), Float(wp.position.z)))
                        break
                    }

                    let isCCW: Bool
                    if case .arcCCW = wp.motion { isCCW = true } else { isCCW = false }

                    let cx = Double(center.x)
                    let cy = Double(center.y)
                    let radius = hypot(prev.position.x - cx, prev.position.y - cy)
                    let startAngle = atan2(prev.position.y - cy, prev.position.x - cx)
                    var endAngle = atan2(wp.position.y - cy, wp.position.x - cx)

                    // Walk from startAngle to endAngle in the requested direction, wrapping
                    // around as needed so a full sweep is taken rather than the short way.
                    if isCCW {
                        while endAngle <= startAngle { endAngle += 2 * .pi }
                    } else {
                        while endAngle >= startAngle { endAngle -= 2 * .pi }
                    }

                    let steps = max(2, segmentsPerArc)
                    for i in 1...steps {
                        let t = Double(i) / Double(steps)
                        let angle = startAngle + (endAngle - startAngle) * t
                        let x = cx + radius * cos(angle)
                        let y = cy + radius * sin(angle)
                        let z = prev.position.z + (wp.position.z - prev.position.z) * t
                        points.append(SIMD3<Float>(Float(x), Float(y), Float(z)))
                    }
            }
            previous = wp
        }

        return points
    }

    // Helper to build RenderVertex array with computed path distances
    private func buildVertices(points: [SIMD3<Float>], color: SIMD4<Float>, zOffset: Float) -> [RenderVertex] {
        var vertices: [RenderVertex] = []
        var totalDistance: Float = 0.0

        for i in 0..<points.count {
            let pt = SIMD3<Float>(points[i].x, points[i].y, points[i].z + zOffset)
            if i > 0 {
                totalDistance += simd_distance(points[i], points[i - 1])
            }
            vertices.append(RenderVertex(position: pt, color: color, dist: totalDistance))
        }
        return vertices
    }
}
