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

/// What a `RenderObject` represents, for the handful of cases where upstream
/// code needs to find one again inside a scene array (e.g. swapping in a
/// freshly-built stock wireframe whenever `CAMModel.selectedStockMaterial`
/// changes, or refreshing the toolpath preview whenever a G-code file
/// (re)loads, without disturbing the other objects in the scene).
/// Nothing about rendering depends on this — it's purely a lookup tag.
enum RenderRole: Hashable {
    case stock
    /// G0 rapid moves, tessellated from `GCodeParser`'s `ToolpathSegment`s.
    case toolpathRapid
    /// G1/G2/G3 cutting and arc moves, tessellated the same way.
    case toolpathCutting
}

/// A single drawable "thing" — a toolpath, the stock outline, a position marker, etc.
/// Pure CPU-side data: no `MTLDevice`, no `MTLBuffer`. The model builds these;
/// only `MetalRenderer` knows how to turn them into GPU buffers.
struct RenderObject: Identifiable {
    let id = UUID()
    var role: RenderRole? = nil
    var points: [SIMD3<Float>]
    var color: SIMD4<Float>
    var primitive: RenderPrimitive = .lineStrip
    var isDashed: Bool = false
    var dashLength: Float = 5.0
    /// Invisible triangle geometry (3 points per triangle) for a solid this
    /// object represents. Never drawn on screen — `MetalRenderer` only uses
    /// it to populate the depth buffer, so that `points` edges genuinely
    /// behind this solid's surface can be detected as occluded and drawn
    /// dashed. Without this, a wireframe shape has no "inside" as far as
    /// the GPU is concerned: an edge is only ever hidden by *another edge*
    /// landing on the same pixel, never by the surface it's actually behind.
    var occluderFaces: [SIMD3<Float>] = []
}

/// Find-and-replace helpers keyed by `RenderRole`, so callers holding a full
/// scene array (axes + stock + toolpath preview + marker, etc.) can update
/// just the one object that changed.
extension Array where Element == RenderObject {
    /// Swaps in `object` for whichever existing element shares its `role`,
    /// leaving everything else in the scene untouched. Appends it if the
    /// scene doesn't have one of that role yet.
    mutating func updating(_ object: RenderObject) {
        guard let role = object.role else {
            append(object)
            return
        }
        if let index = firstIndex(where: { $0.role == role }) {
            self[index] = object
        } else {
            append(object)
        }
    }

    /// Removes every existing element whose role is in `roles`, then appends
    /// `objects` in their place. Unlike `updating(_:)` (one object, matched
    /// and swapped 1:1), this is for a *group* that can grow or shrink
    /// between updates — e.g. a reloaded G-code file might now have rapid
    /// moves where it didn't before, or vice versa, so stale leftovers can't
    /// just be matched by role and overwritten in place.
    mutating func replacing(roles: Set<RenderRole>, with objects: [RenderObject]) {
        removeAll { element in element.role.map(roles.contains) ?? false }
        append(contentsOf: objects)
    }
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

        // Invisible faces for the depth pre-pass — see `occluderFaces` doc.
        // Two triangles per face, 6 faces. Winding is irrelevant here since
        // this geometry is never color-drawn and the depth-only pipeline
        // doesn't cull.
        let occluderFaces: [SIMD3<Float>] = [
            // Bottom (z = bottomZ)
            c000, c100, c110,  c000, c110, c010,
            // Top (z = topZ)
            c001, c101, c111,  c001, c111, c011,
            // Front (y = minY)
            c000, c100, c101,  c000, c101, c001,
            // Back (y = maxY)
            c010, c110, c111,  c010, c111, c011,
            // Left (x = minX)
            c000, c010, c011,  c000, c011, c001,
            // Right (x = maxX)
            c100, c110, c111,  c100, c111, c101,
        ]

        return RenderObject(role: .stock, points: points, color: color, primitive: .lineList, occluderFaces: occluderFaces)
    }

    /// Wireframe stock preview built straight from a `StockMaterial` — picks
    /// the right shape for `stock.geometry` (box / cylinder / disk) and sizes
    /// it from that geometry's own dimensions, in millimeters, so this is
    /// always in sync with whatever `MaterialPanelView` last set on
    /// `CAMModel.selectedStockMaterial`. Origin convention matches
    /// `StockLayer`'s 2D drawing: the shape's bounding box starts at
    /// (0, 0) and grows into +X/+Y, with the top face at Z = 0 and material
    /// extending downward from there (matching `stockBox(minX:...)`'s own
    /// defaults, which are just a rectangular stock with width 100 / height
    /// 50 / depth 10).
    static func stockBox(for stock: StockMaterial,
                          color: SIMD4<Float> = SIMD4<Float>(0.6, 0.2, 0.85, 1.0)) -> RenderObject {
        switch stock.geometry {
        case let .rectangular(width, height, depth):
            return stockBox(minX: 0, maxX: Float(width),
                             minY: 0, maxY: Float(height),
                             topZ: 0, bottomZ: Float(-depth),
                             color: color)

        case let .cylindrical(diameter, length):
            return stockCylinder(diameter: Float(diameter), height: Float(length), color: color)

        case let .disk(outerDiameter, innerDiameter, depth):
            return stockDisk(outerDiameter: Float(outerDiameter),
                              innerDiameter: Float(innerDiameter),
                              depth: Float(depth),
                              color: color)
        }
    }

    /// Wireframe cylinder (round stock, e.g. for a rotary/4th-axis job) —
    /// top/bottom rings, a handful of vertical struts so it still reads as
    /// round from any angle, and fan/quad-triangulated occluder faces so it
    /// hidden-lines correctly like `stockBox()` does.
    private static func stockCylinder(diameter: Float, height: Float,
                                       segments: Int = 48, strutCount: Int = 4,
                                       color: SIMD4<Float>) -> RenderObject {
        let radius = max(0, diameter) / 2
        let centerXY = SIMD2<Float>(radius, radius) // bounding box starts at (0, 0), same as StockLayer
        let topZ: Float = 0
        let bottomZ = -height

        func ring(_ i: Int, z: Float) -> SIMD3<Float> {
            let t = Float(i) / Float(segments)
            let angle = t * 2 * Float.pi
            return SIMD3<Float>(centerXY.x + radius * cos(angle), centerXY.y + radius * sin(angle), z)
        }

        var points: [SIMD3<Float>] = []
        for i in 0..<segments {
            points.append(ring(i, z: topZ)); points.append(ring(i + 1, z: topZ))
        }
        for i in 0..<segments {
            points.append(ring(i, z: bottomZ)); points.append(ring(i + 1, z: bottomZ))
        }
        let clampedStruts = max(0, strutCount)
        for s in 0..<clampedStruts {
            let i = (s * segments) / max(1, clampedStruts)
            points.append(ring(i, z: topZ)); points.append(ring(i, z: bottomZ))
        }

        let topCenter = SIMD3<Float>(centerXY.x, centerXY.y, topZ)
        let bottomCenter = SIMD3<Float>(centerXY.x, centerXY.y, bottomZ)
        var occluderFaces: [SIMD3<Float>] = []
        for i in 0..<segments {
            // Caps: fan-triangulated from the center point.
            occluderFaces.append(topCenter); occluderFaces.append(ring(i, z: topZ)); occluderFaces.append(ring(i + 1, z: topZ))
            occluderFaces.append(bottomCenter); occluderFaces.append(ring(i + 1, z: bottomZ)); occluderFaces.append(ring(i, z: bottomZ))

            // Side wall: one quad (2 triangles) per segment.
            let t0 = ring(i, z: topZ), t1 = ring(i + 1, z: topZ)
            let b0 = ring(i, z: bottomZ), b1 = ring(i + 1, z: bottomZ)
            occluderFaces.append(t0); occluderFaces.append(b0); occluderFaces.append(b1)
            occluderFaces.append(t0); occluderFaces.append(b1); occluderFaces.append(t1)
        }

        return RenderObject(role: .stock, points: points, color: color, primitive: .lineList, occluderFaces: occluderFaces)
    }

    /// Wireframe disk/washer (outer stock with a bored-out center, e.g. a
    /// ring blank) — outer + inner rings top and bottom, struts on the
    /// outer wall only (a strut across the hole would read as a spoke that
    /// isn't actually part of the stock).
    private static func stockDisk(outerDiameter: Float, innerDiameter: Float, depth: Float,
                                   segments: Int = 48, strutCount: Int = 4,
                                   color: SIMD4<Float>) -> RenderObject {
        let outerRadius = max(0, outerDiameter) / 2
        let innerRadius = max(0, min(innerDiameter, outerDiameter)) / 2
        let centerXY = SIMD2<Float>(outerRadius, outerRadius) // bounding box starts at (0, 0), same as StockLayer
        let topZ: Float = 0
        let bottomZ = -depth
        let hasHole = innerRadius > 0

        func ring(_ i: Int, radius: Float, z: Float) -> SIMD3<Float> {
            let t = Float(i) / Float(segments)
            let angle = t * 2 * Float.pi
            return SIMD3<Float>(centerXY.x + radius * cos(angle), centerXY.y + radius * sin(angle), z)
        }

        var points: [SIMD3<Float>] = []
        for i in 0..<segments {
            points.append(ring(i, radius: outerRadius, z: topZ)); points.append(ring(i + 1, radius: outerRadius, z: topZ))
        }
        for i in 0..<segments {
            points.append(ring(i, radius: outerRadius, z: bottomZ)); points.append(ring(i + 1, radius: outerRadius, z: bottomZ))
        }
        if hasHole {
            for i in 0..<segments {
                points.append(ring(i, radius: innerRadius, z: topZ)); points.append(ring(i + 1, radius: innerRadius, z: topZ))
            }
            for i in 0..<segments {
                points.append(ring(i, radius: innerRadius, z: bottomZ)); points.append(ring(i + 1, radius: innerRadius, z: bottomZ))
            }
        }
        let clampedStruts = max(0, strutCount)
        for s in 0..<clampedStruts {
            let i = (s * segments) / max(1, clampedStruts)
            points.append(ring(i, radius: outerRadius, z: topZ)); points.append(ring(i, radius: outerRadius, z: bottomZ))
        }

        let topCenter = SIMD3<Float>(centerXY.x, centerXY.y, topZ)
        let bottomCenter = SIMD3<Float>(centerXY.x, centerXY.y, bottomZ)
        var occluderFaces: [SIMD3<Float>] = []
        for i in 0..<segments {
            let to0 = ring(i, radius: outerRadius, z: topZ), to1 = ring(i + 1, radius: outerRadius, z: topZ)
            let bo0 = ring(i, radius: outerRadius, z: bottomZ), bo1 = ring(i + 1, radius: outerRadius, z: bottomZ)

            // Outer wall: one quad per segment.
            occluderFaces.append(to0); occluderFaces.append(bo0); occluderFaces.append(bo1)
            occluderFaces.append(to0); occluderFaces.append(bo1); occluderFaces.append(to1)

            if hasHole {
                let ti0 = ring(i, radius: innerRadius, z: topZ), ti1 = ring(i + 1, radius: innerRadius, z: topZ)
                let bi0 = ring(i, radius: innerRadius, z: bottomZ), bi1 = ring(i + 1, radius: innerRadius, z: bottomZ)

                // Inner (bore) wall — wound the opposite way from the outer
                // wall since it's the inside surface of the hole.
                occluderFaces.append(ti0); occluderFaces.append(bi1); occluderFaces.append(bi0)
                occluderFaces.append(ti0); occluderFaces.append(ti1); occluderFaces.append(bi1)

                // Top/bottom annulus between the inner and outer ring.
                occluderFaces.append(to0); occluderFaces.append(to1); occluderFaces.append(ti1)
                occluderFaces.append(to0); occluderFaces.append(ti1); occluderFaces.append(ti0)

                occluderFaces.append(bo0); occluderFaces.append(bi0); occluderFaces.append(bi1)
                occluderFaces.append(bo0); occluderFaces.append(bi1); occluderFaces.append(bo1)
            } else {
                // No hole: falls back to a solid fan-triangulated disk cap.
                occluderFaces.append(topCenter); occluderFaces.append(to0); occluderFaces.append(to1)
                occluderFaces.append(bottomCenter); occluderFaces.append(bo1); occluderFaces.append(bo0)
            }
        }

        return RenderObject(role: .stock, points: points, color: color, primitive: .lineList, occluderFaces: occluderFaces)
    }

    /// Turns `GCodeParser`'s flat `ToolpathSegment` list — already plain
    /// `SIMD3<Float>` start/end coordinates, that's all `GCodeParser` ever
    /// produces — into `RenderObject`s `MetalCanvasView` can draw.
    ///
    /// Segments are split into two groups by motion type rather than merged
    /// into one object: rapids (G0) are drawn in a different color from
    /// cutting/arc moves (G1/G2/G3), the same convention most CAM viewers
    /// use so a rapid reposition doesn't read as a cut. Both are solid
    /// lines. Both groups use `.lineList`, not `.lineStrip` — segments are
    /// independent moves, often with gaps between them (e.g. a rapid up,
    /// over, and back down), and `.lineStrip` would draw a spurious
    /// connecting line across every gap since it always joins consecutive
    /// points.
    static func toolpath(from segments: [ToolpathSegment],
                          rapidColor: SIMD4<Float> = SIMD4<Float>(1.0, 0.85, 0.2, 1.0),
                          cuttingColor: SIMD4<Float> = SIMD4<Float>(0.2, 0.8, 1.0, 1.0)) -> [RenderObject] {
        guard !segments.isEmpty else {
            return []
        }

        var rapidPoints: [SIMD3<Float>] = []
        var cuttingPoints: [SIMD3<Float>] = []
        rapidPoints.reserveCapacity(segments.count * 2)
        cuttingPoints.reserveCapacity(segments.count * 2)

        for segment in segments {
            if segment.flags & ToolpathFlags.rapid != 0 {
                rapidPoints.append(segment.start)
                rapidPoints.append(segment.end)
            } else {
                cuttingPoints.append(segment.start)
                cuttingPoints.append(segment.end)
            }
        }

        var objects: [RenderObject] = []
        if !rapidPoints.isEmpty {
            objects.append(RenderObject(role: .toolpathRapid,
                                        points: rapidPoints,
                                        color: rapidColor,
                                        primitive: .lineList))
        }
        if !cuttingPoints.isEmpty {
            objects.append(RenderObject(role: .toolpathCutting,
                                        points: cuttingPoints,
                                        color: cuttingColor,
                                        primitive: .lineList))
        }
        return objects
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
    /// needs its own color (red/green/blue). Each axis is drawn as 3 parallel
    /// strands arranged around the centerline (poor man's thick line — Metal's
    /// line primitives are always hairline-width, there's no `glLineWidth`
    /// equivalent) plus a small cone arrowhead at the tip.
    static func axes(length: Float = 7.5, thickness: Float = 0.09) -> [RenderObject] {
        let headLength = min(length * 0.15, 8)
        let headRadius = thickness * 3
        let x = axisArrow(direction: SIMD3<Float>(1, 0, 0), length: length, thickness: thickness,
                          color: SIMD4<Float>(1.0, 0.15, 0.15, 1.0), headLength: headLength, headRadius: headRadius)
        let y = axisArrow(direction: SIMD3<Float>(0, 1, 0), length: length, thickness: thickness,
                          color: SIMD4<Float>(0.15, 1.0, 0.15, 1.0), headLength: headLength, headRadius: headRadius)
        let z = axisArrow(direction: SIMD3<Float>(0, 0, 1), length: length, thickness: thickness,
                          color: SIMD4<Float>(0.15, 0.45, 1.0, 1.0), headLength: headLength, headRadius: headRadius)
        return [x, y, z]
    }

    /// Builds one axis: a 3-strand thick shaft from the origin plus a cone
    /// arrowhead at the tip, all as a single `.lineList` object.
    private static func axisArrow(direction: SIMD3<Float>,
                                  length: Float,
                                  thickness: Float,
                                  color: SIMD4<Float>,
                                  headLength: Float,
                                  headRadius: Float,
                                  headSegments: Int = 10) -> RenderObject {
        let dir = simd_normalize(direction)
        let tip = dir * length
        let shaftEnd = tip - dir * headLength // shaft stops where the arrowhead begins
        let (u, v) = perpendicularBasis(for: dir)

        var points: [SIMD3<Float>] = []

        // Shaft: 3 parallel strands spaced evenly around the centerline, so
        // the line reads as thick from most viewing angles rather than just one.
        let strands = 3
        for i in 0..<strands {
            let angle = Float(i) * (2 * .pi / Float(strands))
            let offset = thickness * (cos(angle) * u + sin(angle) * v)
            points.append(offset)
            points.append(shaftEnd + offset)
        }

        // Arrowhead: a ring at the base of the cone plus struts converging
        // to the tip — same construction as `marker(at:)`'s cylinder, just
        // tapering to a point instead of a second ring.
        let segs = max(3, headSegments)
        func ringPoint(_ i: Int) -> SIMD3<Float> {
            let t = Float(i) / Float(segs)
            let angle = t * 2 * .pi
            return shaftEnd + headRadius * (cos(angle) * u + sin(angle) * v)
        }
        for i in 0..<segs {
            points.append(ringPoint(i))
            points.append(ringPoint(i + 1))
        }
        for i in 0..<segs {
            points.append(ringPoint(i))
            points.append(tip)
        }

        return RenderObject(points: points, color: color, primitive: .lineList)
    }

    /// Any two unit vectors perpendicular to `direction` and to each other —
    /// used to build geometry (shaft strands, cone rings) around an arbitrary axis.
    private static func perpendicularBasis(for direction: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let d = simd_normalize(direction)
        // Pick a helper vector that's never near-parallel to `d`, so the cross
        // product below doesn't degenerate.
        let helper = abs(d.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        let u = simd_normalize(simd_cross(d, helper))
        let v = simd_cross(d, u)
        return (u, v)
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
