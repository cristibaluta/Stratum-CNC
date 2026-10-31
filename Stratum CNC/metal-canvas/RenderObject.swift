//
//  RenderObject.swift
//  Stratum CNC
//

import Foundation
import simd

/// The colors the canvas draws its objects in. One place, so the objects
/// list's tints (`CanvasLayer.color`) and the coordinate pills always match
/// what is actually on the canvas.
enum CanvasPalette {
    static let stock       = SIMD4<Float>(0.6, 0.2, 0.85, 1.0)
    static let rapid       = SIMD4<Float>(1.0, 0.85, 0.2, 1.0)
    static let cutting     = SIMD4<Float>(0.2, 0.8, 1.0, 1.0)
    static let boundingBox = SIMD4<Float>(0.2, 0.75, 0.35, 1.0)
    static let tool        = SIMD4<Float>(0.6, 0.62, 0.66, 1.0)
    static let workbed     = SIMD4<Float>(0.55, 0.6, 0.65, 1.0)
    static let anchor      = SIMD4<Float>(0.95, 0.55, 0.15, 1.0)
    static let ruler       = anchor
}

/// How the points in a `RenderObject` should be connected.
/// Mirrors the handful of `MTLPrimitiveType` cases the renderer actually uses,
/// without pulling MetalKit into the model layer.
enum RenderPrimitive {
    case lineStrip  // consecutive points joined into one continuous path
    case lineList   // points consumed in disconnected pairs (start, end, start, end, ...)
}

/// One vertex of a lit, filled triangle mesh (position + surface normal).
/// Deliberately the same type the heightmap surface uses, so solid objects
/// such as the tool marker can be drawn by the heightmap's shaded-triangle
/// pipeline without a second vertex layout to keep in sync.
typealias SolidVertex = HeightmapMesh.Vertex

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
    /// The cutter itself, drawn at true size at the machine's current position.
    case tool
    /// Static machine fixture: the flat outline of the work bed the stock
    /// sits on. Lives at the stock's bottom Z, so it's rebuilt whenever the
    /// stock changes (see `CanvasSceneModel.updateStock`).
    case workbed
    /// Static machine fixture: the L-shaped anchor (fence) the stock is
    /// pushed against. Same Z/rebuild rules as `.workbed`.
    case anchor
    /// Static machine fixture: the graduated ruler along the anchor's
    /// inside edges. Same Z/rebuild rules as `.workbed` and `.anchor`.
    /// In the controller's scene the ruler is part of the `.anchor` object
    /// (see `anchor(z:...rulerLength:)`); this role is the ruler as an
    /// object of its own, which CAM's 2D view still uses.
    case ruler
    /// Dotted rectangle around the loaded program's cutting moves, grown
    /// outward by the radius of the tool that cuts each edge — i.e. the
    /// footprint the finished job occupies. Follows `xyOffset` like the
    /// toolpath it was measured from. Rebuilt by
    /// `CanvasSceneModel.updateBoundingBox`.
    case boundingBox
    /// Rapid moves of the macro currently selected in the controller's MACROS
    /// tab. Kept apart from `.toolpathRapid` so previewing a macro never
    /// touches the loaded program's geometry: the program is only hidden, and
    /// comes back without a reload. Follows `xyOffset` like the toolpath.
    case macroRapid
    /// Cutting moves of the previewed macro. See `.macroRapid`.
    case macroCutting
    /// The XYZ axis gizmo at the origin (all three arrows). Tagged only so
    /// the canvas's objects list can switch it off — see `CanvasLayer`.
    case axes
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
    /// Caps how many of `points` the renderer should actually draw, without
    /// touching `points` itself. `nil` draws everything.
    ///
    /// This exists for the G-code scrubber: it lets `points` hold the *full*
    /// toolpath (built once, when a file loads) while the visible portion is
    /// narrowed on every scrub tick just by changing this number — no
    /// re-tessellation, and (see `MetalRenderer.updateGeometry`) no GPU
    /// buffer rebuild, since the object's `id` stays the same as long as
    /// only this field changes on an existing array element.
    var visibleVertexCount: Int? = nil
    /// Invisible triangle geometry (3 points per triangle) for a solid this
    /// object represents. Never drawn on screen — `MetalRenderer` only uses
    /// it to populate the depth buffer, so that `points` edges genuinely
    /// behind this solid's surface can be detected as occluded and drawn
    /// dashed. Without this, a wireframe shape has no "inside" as far as
    /// the GPU is concerned: an edge is only ever hidden by *another edge*
    /// landing on the same pixel, never by the surface it's actually behind.
    var occluderFaces: [SIMD3<Float>] = []
    /// Visible, lit, filled triangles (3 vertices per triangle) drawn in
    /// `color`. Independent of `points`: an object can carry lines, a solid,
    /// or both. Unlike `occluderFaces` these are actually drawn — see
    /// `MetalRenderer.drawSolids`. The tool marker is the only user so far.
    var solidTriangles: [SolidVertex] = []
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

    /// Narrows how much of the existing element with role `role` gets drawn,
    /// in place — the element's `id` (and therefore its GPU buffer, see
    /// `MetalRenderer.updateGeometry`) is left untouched. Does nothing if no
    /// element has that role. Deliberately the *only* mutation the scrubber
    /// performs on the scene: `updating(_:)` and `replacing(roles:with:)`
    /// both swap in freshly-built objects (new `id`s), which is exactly what
    /// forces a GPU buffer rebuild — fine for an occasional stock/toolpath
    /// reload, too slow to do on every scrub tick.
    mutating func settingVisibleVertexCount(_ count: Int?, forRole role: RenderRole) {
        guard let index = firstIndex(where: { $0.role == role }) else {
            return
        }
        self[index].visibleVertexCount = count
    }
}

// MARK: - Common shapes

extension RenderObject {

    /// Wireframe box, e.g. for previewing stock material.
    static func stockBox(minX: Float = 0, maxX: Float = 100,
                          minY: Float = 0, maxY: Float = 50,
                          topZ: Float = 0, bottomZ: Float = -10,
                          color: SIMD4<Float> = CanvasPalette.stock) -> RenderObject {

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

    static func stockBox(for stock: StockMaterial, color: SIMD4<Float> = CanvasPalette.stock) -> RenderObject {

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
            occluderFaces.append(topCenter)
            occluderFaces.append(ring(i, z: topZ))
            occluderFaces.append(ring(i + 1, z: topZ))
            occluderFaces.append(bottomCenter)
            occluderFaces.append(ring(i + 1, z: bottomZ))
            occluderFaces.append(ring(i, z: bottomZ))

            // Side wall: one quad (2 triangles) per segment.
            let t0 = ring(i, z: topZ), t1 = ring(i + 1, z: topZ)
            let b0 = ring(i, z: bottomZ), b1 = ring(i + 1, z: bottomZ)
            occluderFaces.append(t0)
            occluderFaces.append(b0)
            occluderFaces.append(b1)
            occluderFaces.append(t0)
            occluderFaces.append(b1)
            occluderFaces.append(t1)
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

    // MARK: Machine fixtures (static, flat)

    /// Every fixture role `fixtures(bottomZ:roles:)`/`fixtures(for:roles:)`
    /// know how to build. The default `roles` argument on both — the
    /// controller's "every fixture" scene — is defined in terms of this so
    /// adding a new fixture role only means adding it here once.
    static let allFixtureRoles: Set<RenderRole> = [.workbed, .anchor, .ruler]

    /// The static fixtures — work bed, and the anchor with its ruler — at
    /// height `z`. `roles` picks what to build (default: all of it, the
    /// controller's scene, where the ruler is built into the anchor object
    /// rather than as a separate one). CAM's 2D view, which draws its own
    /// stock and isn't positioned relative to the machine bed at all, asks
    /// for just `[.ruler]` here instead.
    ///
    /// `bedOrigin`/`bedSize` place the work bed (its minimum corner and
    /// extent, in canvas coordinates — see `MachineLayout`); the defaults are
    /// the original 200 × 200 mm bed with the anchor at its bottom-left.
    static func fixtures(bottomZ z: Float,
                         roles: Set<RenderRole> = allFixtureRoles,
                         bedOrigin: SIMD2<Float> = SIMD2<Float>(-15, -15),
                         bedSize: SIMD2<Float> = SIMD2<Float>(200, 200)) -> [RenderObject] {
        var result: [RenderObject] = []
        if roles.contains(.workbed) { result.append(workbed(z: z, origin: bedOrigin, width: bedSize.x, height: bedSize.y)) }
        // The ruler is part of the anchor: one object when both are wanted.
        // A ruler alone (the 2D view's `[.ruler]`) is still its own object.
        if roles.contains(.anchor) {
            result.append(anchor(z: z, rulerLength: roles.contains(.ruler) ? 80 : 0))
        } else if roles.contains(.ruler) {
            result.append(ruler(z: z))
        }
        return result
    }

    /// The fixtures placed at `stock`'s bottom face, which is where they sit
    /// physically. Their Z follows the stock's depth, so `CanvasSceneModel`
    /// rebuilds them alongside the stock box whenever the stock changes.
    /// See `fixtures(bottomZ:roles:)` for `roles`.
    static func fixtures(for stock: StockMaterial,
                         roles: Set<RenderRole> = allFixtureRoles,
                         bedOrigin: SIMD2<Float> = SIMD2<Float>(-15, -15),
                         bedSize: SIMD2<Float> = SIMD2<Float>(200, 200)) -> [RenderObject] {
        fixtures(bottomZ: bottomZ(of: stock), roles: roles, bedOrigin: bedOrigin, bedSize: bedSize)
    }

    /// Z of `stock`'s bottom face — the same value each case of
    /// `stockBox(for:)` uses for its own `bottomZ`.
    static func bottomZ(of stock: StockMaterial) -> Float {
        switch stock.geometry {
            case let .rectangular(_, _, depth):  return -Float(depth)
            case let .cylindrical(_, length):    return -Float(length)
            case let .disk(_, _, depth):         return -Float(depth)
        }
    }

    /// The work bed: a flat, closed rectangular outline in the XY plane at
    /// `z` — no thickness, no faces. Defaults to 200×200mm starting at
    /// (-15, -15).
    ///
    /// Static: no `xyOffset` is applied to `.workbed` (see
    /// `MetalRenderer.drawBatch`), so it stays where the machine physically is
    /// while the job is nudged around on top of it.
    static func workbed(z: Float,
                        origin: SIMD2<Float> = SIMD2<Float>(-15, -15),
                        width: Float = 200,
                        height: Float = 200,
                        color: SIMD4<Float> = CanvasPalette.workbed) -> RenderObject {

        let corners = [
            origin,
            SIMD2<Float>(origin.x + width, origin.y),
            SIMD2<Float>(origin.x + width, origin.y + height),
            SIMD2<Float>(origin.x,         origin.y + height)
        ]
        return flatOutline(corners, z: z, role: .workbed, color: color)
    }

    /// The anchor: a flat, closed L-shaped outline in the XY plane at `z`.
    ///
    /// Positioned by its *inside* corner (default: the work origin, 0,0), so
    /// the L wraps around the origin's lower-left: one arm runs along +X below
    /// it, the other along +Y to its left. `legLength` is each arm's full
    /// outer length, measured from the outer corner; `thickness` is the arm
    /// width. Each arm's *inside* edge is therefore `legLength - thickness`
    /// long — 85 mm with the defaults. With the defaults the outer corner
    /// lands on (-15, -15) — exactly the work bed's origin corner.
    ///
    ///   (not to scale; default coordinates shown)
    ///
    ///   (-15,85) ┌──┐ (0,85)
    ///            │  │
    ///            │  └──────┐ (85,0)     ← inner elbow is `insideCorner` (0,0)
    ///            └─────────┘ (85,-15)
    ///         (-15,-15) = outer corner
    ///
    /// With `rulerLength` above zero the anchor also carries its ruler (see
    /// `ruler(z:insideCorner:length:color:)`): the graduations along the two
    /// inside edges are part of the *same* object, so the anchor and its
    /// ruler show, hide and move as one. The outline is then a `.lineList`
    /// rather than a closed `.lineStrip`, so both can share a single
    /// buffer; it draws identically.
    ///
    /// Static, like `workbed` — no `xyOffset`.
    static func anchor(z: Float,
                       insideCorner: SIMD2<Float> = .zero,
                       legLength: Float = 100,
                       thickness: Float = 15,
                       rulerLength: Float = 0,
                       color: SIMD4<Float> = CanvasPalette.anchor) -> RenderObject {

        let outer = insideCorner - SIMD2<Float>(repeating: thickness)

        let corners = [
            outer,                                                       // outer corner
            SIMD2<Float>(outer.x + legLength, outer.y),                  // X arm, far end, outer edge
            SIMD2<Float>(outer.x + legLength, insideCorner.y),           // X arm, far end, inner edge
            insideCorner,                                                // inside corner
            SIMD2<Float>(insideCorner.x,      outer.y + legLength),      // Y arm, far end, inner edge
            SIMD2<Float>(outer.x,             outer.y + legLength)       // Y arm, far end, outer edge
        ]
        guard rulerLength > 0 else {
            return flatOutline(corners, z: z, role: .anchor, color: color)
        }

        // Outline as separate segments (closing back to the first corner),
        // then the ruler's ticks, all in one line list.
        var points: [SIMD3<Float>] = []
        for index in corners.indices {
            let from = corners[index]
            let to = corners[(index + 1) % corners.count]
            points.append(SIMD3<Float>(from.x, from.y, z))
            points.append(SIMD3<Float>(to.x, to.y, z))
        }
        points += rulerPoints(z: z, insideCorner: insideCorner, length: rulerLength)

        return RenderObject(role: .anchor, points: points, color: color, primitive: .lineList)
    }

    /// A ruler along the anchor's two *inside* edges, measured from the
    /// inside corner: one running along +X, one along +Y, `length` mm each
    /// (default 80 = 8 cm). Ticks point into the anchor's arms — away from
    /// the work area — so the graduations sit on the fence itself and are
    /// never hidden under the stock.
    ///
    /// Tick sizes: 1 mm (short), 5 mm (medium), 10 mm (long). There's no
    /// text rendering in this renderer, so the 10 mm marks are the numbering.
    ///
    /// Static, like the anchor — no `xyOffset`. The default anchor's arms
    /// have 85 mm of inside edge, so the whole 80 mm ruler sits on the
    /// fence. If `length` is ever raised past the arms' inside edge, the
    /// extra ticks stand on the bed instead.
    static func ruler(z: Float,
                      insideCorner: SIMD2<Float> = .zero,
                      length: Float = 80,
                      color: SIMD4<Float> = CanvasPalette.ruler) -> RenderObject {
        RenderObject(role: .ruler,
                     points: rulerPoints(z: z, insideCorner: insideCorner, length: length),
                     color: color,
                     primitive: .lineList)
    }

    /// The ruler's line segments (baselines and ticks), shared by the
    /// standalone `ruler` and the anchor that carries it.
    private static func rulerPoints(z: Float, insideCorner: SIMD2<Float>, length: Float) -> [SIMD3<Float>] {

        var points: [SIMD3<Float>] = []
        let x0 = insideCorner.x
        let y0 = insideCorner.y

        // The two baselines the ticks hang off.
        points.append(SIMD3<Float>(x0, y0, z))
        points.append(SIMD3<Float>(x0 + length, y0, z))
        points.append(SIMD3<Float>(x0, y0, z))
        points.append(SIMD3<Float>(x0, y0 + length, z))

        for mm in 0...Int(length.rounded(.down)) {
            let tick: Float = mm % 10 == 0 ? 6 : (mm % 5 == 0 ? 4 : 2)
            let d = Float(mm)

            // X ruler: along y = insideCorner.y, ticks toward -Y.
            points.append(SIMD3<Float>(x0 + d, y0, z))
            points.append(SIMD3<Float>(x0 + d, y0 - tick, z))

            // Y ruler: along x = insideCorner.x, ticks toward -X.
            points.append(SIMD3<Float>(x0, y0 + d, z))
            points.append(SIMD3<Float>(x0 - tick, y0 + d, z))
        }

        return points
    }

    /// Closed polygon outline at constant `z`. One `.lineStrip` that returns
    /// to its first point. No `occluderFaces` on purpose: these are 2D, so
    /// there's no solid for anything to hide behind.
    private static func flatOutline(_ corners: [SIMD2<Float>],
                                    z: Float,
                                    role: RenderRole,
                                    color: SIMD4<Float>) -> RenderObject {
        var points = corners.map { SIMD3<Float>($0.x, $0.y, z) }
        if let first = points.first {
            points.append(first)
        }
        return RenderObject(role: role, points: points, color: color, primitive: .lineStrip)
    }

    /// The job's bounding box: a flat, closed, dashed rectangle in the XY
    /// plane at `z` (default 0, the stock's top face), from `min` (bottom-
    /// left corner — the job's origin) to `max`. Drawn in toolpath
    /// coordinates; `MetalRenderer` shifts it by `xyOffset` like the
    /// toolpath itself (see `drawOffset(for:)`).
    ///
    /// The dash length scales with the job so the pattern stays readable on
    /// both a 20 mm part and a 300 mm one (the dash is in world millimeters,
    /// not pixels).
    static func boundingBox(min: SIMD2<Float>,
                            max: SIMD2<Float>,
                            z: Float = 0,
                            color: SIMD4<Float> = CanvasPalette.boundingBox) -> RenderObject {
        let corners = [
            min,
            SIMD2<Float>(max.x, min.y),
            max,
            SIMD2<Float>(min.x, max.y)
        ]
        var object = flatOutline(corners, z: z, role: .boundingBox, color: color)
        let longestSide = Swift.max(max.x - min.x, max.y - min.y)
        object.isDashed = true
        object.dashLength = Swift.min(Swift.max(longestSide / 80, 0.5), 4)
        return object
    }

    static func toolpath(from segments: [ToolpathSegment],
                         rapidColor: SIMD4<Float> = CanvasPalette.rapid,
                         cuttingColor: SIMD4<Float> = CanvasPalette.cutting,
                         rapidRole: RenderRole = .toolpathRapid,
                         cuttingRole: RenderRole = .toolpathCutting) -> [RenderObject] {

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
            objects.append(RenderObject(role: rapidRole,
                                        points: rapidPoints,
                                        color: rapidColor,
                                        primitive: .lineList))
        }
        if !cuttingPoints.isEmpty {
            objects.append(RenderObject(role: cuttingRole,
                                        points: cuttingPoints,
                                        color: cuttingColor,
                                        primitive: .lineList))
        }
        return objects
    }

    /// The cutter as a solid, drawn at true size with its tip at
    /// `tipPosition`. The body is a surface of revolution around the vertical
    /// axis, shaped by `shape` the same way `ToolFootprint` shapes the cut:
    ///
    /// - `.flat` (end mills, drills, thread mills): flat-bottomed cylinder.
    /// - `.ball`: hemispherical tip, radius = tool radius.
    /// - `.cone` (V-bits, engraving bits): cone from the tip up to the full diameter,
    ///   half-angle from `tipAngleDegrees` (flat if none is on file, same
    ///   fallback as `ToolFootprint.surfaceZ`).
    ///
    /// Above the tip shape the tool continues as a full-diameter cylinder up
    /// to `length` above the tip. Triangles wind counter-clockwise seen from
    /// outside and carry analytic normals (smooth on the ball nose, hard
    /// edges everywhere else).
    static func tool(at tipPosition: SIMD3<Float>,
                     diameter: Double,
                     length: Double,
                     shape: ToolShape = .flat,
                     tipAngleDegrees: Double? = nil,
                     segments: Int = 48,
                     color: SIMD4<Float> = CanvasPalette.tool) -> RenderObject {

        let sides = max(3, segments)
        let radius = Float(max(0, diameter) / 2)
        guard radius > 0 else {
            return RenderObject(role: .tool, points: [], color: color)
        }
        let totalLength = Float(max(0, length))

        // Profile of the tool from the tip upward: (radius, height above the
        // tip) plus the outward surface normal in that same (radial, up)
        // plane. Consecutive points form one lathe band each; a hard edge is
        // just two points at the same position with different normals.
        struct ProfilePoint {
            var r: Float
            var z: Float
            var nr: Float
            var nz: Float
        }
        var profile: [ProfilePoint] = []

        /// Straight band from (r0, z0) to (r1, z1), flat-shaded. Walking the
        /// profile tip → outside → up → top center makes `(dz, -dr)` the
        /// outward normal for every band type (bottom cap, cone, wall, top cap).
        func addFlat(_ r0: Float, _ z0: Float, _ r1: Float, _ z1: Float) {
            let dr = r1 - r0
            let dz = z1 - z0
            let len = (dr * dr + dz * dz).squareRoot()
            guard len > 0 else {
                return
            }
            let nr = dz / len
            let nz = -dr / len
            profile.append(ProfilePoint(r: r0, z: z0, nr: nr, nz: nz))
            profile.append(ProfilePoint(r: r1, z: z1, nr: nr, nz: nz))
        }

        // Tip shape — everything below `tipHeight`.
        var tipHeight: Float = 0
        switch shape {
            case .ball:
                let arcSteps = 12
                for k in 0...arcSteps {
                    let phi = Float(k) / Float(arcSteps) * (Float.pi / 2)
                    profile.append(ProfilePoint(r: radius * sin(phi),
                                                z: radius - radius * cos(phi),
                                                nr: sin(phi),
                                                nz: -cos(phi)))
                }
                tipHeight = radius

            case .cone:
                if let angle = tipAngleDegrees, angle > 0, angle < 180 {
                    let halfAngle = Float((angle / 2) * .pi / 180)
                    tipHeight = radius / tan(halfAngle)
                    addFlat(0, 0, radius, tipHeight)
                } else {
                    addFlat(0, 0, radius, 0)
                }

            case .flat:
                addFlat(0, 0, radius, 0)
        }

        // Shank / flutes up to `length` above the tip, then the top cap.
        // If `length` is shorter than the tip shape itself, the tip shape
        // wins — better a stubby correct tip than a truncated one.
        let topZ = max(totalLength, tipHeight)
        if topZ > tipHeight {
            addFlat(radius, tipHeight, radius, topZ)
        }
        addFlat(radius, topZ, 0, topZ)

        // Spin the profile around the tool axis.
        var cosines: [Float] = []
        var sines: [Float] = []
        cosines.reserveCapacity(sides + 1)
        sines.reserveCapacity(sides + 1)
        for j in 0...sides {
            let angle = Float(j) / Float(sides) * 2 * Float.pi
            cosines.append(cos(angle))
            sines.append(sin(angle))
        }

        func vertex(_ p: ProfilePoint, _ j: Int) -> SolidVertex {
            SolidVertex(position: SIMD3<Float>(tipPosition.x + p.r * cosines[j],
                                               tipPosition.y + p.r * sines[j],
                                               tipPosition.z + p.z),
                        normal: SIMD3<Float>(p.nr * cosines[j], p.nr * sines[j], p.nz))
        }

        var triangles: [SolidVertex] = []
        triangles.reserveCapacity(max(0, profile.count - 1) * sides * 6)

        for i in 0..<(profile.count - 1) {
            let a = profile[i]
            let b = profile[i + 1]
            // Zero-length band: the seam between two hard-edged runs.
            if a.r == b.r && a.z == b.z {
                continue
            }
            for j in 0..<sides {
                let p00 = vertex(a, j)
                let p01 = vertex(a, j + 1)
                let p10 = vertex(b, j)
                let p11 = vertex(b, j + 1)
                // Bands that start or end on the axis collapse one triangle
                // of the quad to a sliver; skip it.
                if a.r > 0 {
                    triangles.append(contentsOf: [p00, p01, p10])
                }
                if b.r > 0 {
                    triangles.append(contentsOf: [p01, p11, p10])
                }
            }
        }

        return RenderObject(role: .tool, points: [], color: color, solidTriangles: triangles)
    }

    /// Small cylinder marker (e.g. current position, a probe point).
//    static func marker(at point: SIMD3<Float>,
//                        diameter: Float = 6.0,
//                        height: Float = 12.0,
//                        segments: Int = 28,
//                        strutCount: Int = 4,
//                        color: SIMD4<Float> = SIMD4<Float>(1.0, 0.05, 0.05, 1.0)) -> RenderObject {
//        let clampedSegments = max(3, segments)
//        let radius = max(0, diameter) / 2
//        let baseZ = point.z
//        let topZ = point.z + height
//
//        func ringPoint(_ i: Int, z: Float) -> SIMD3<Float> {
//            let t = Float(i) / Float(clampedSegments)
//            let angle = t * 2 * Float.pi
//            let x = point.x + radius * cos(angle)
//            let y = point.y + radius * sin(angle)
//            return SIMD3<Float>(x, y, z)
//        }
//
//        var points: [SIMD3<Float>] = []
//        points.reserveCapacity(clampedSegments * 4 + max(0, strutCount) * 2)
//
//        for i in 0..<clampedSegments {
//            points.append(ringPoint(i, z: baseZ))
//            points.append(ringPoint(i + 1, z: baseZ))
//        }
//        for i in 0..<clampedSegments {
//            points.append(ringPoint(i, z: topZ))
//            points.append(ringPoint(i + 1, z: topZ))
//        }
//
//        let clampedStruts = max(0, strutCount)
//        for s in 0..<clampedStruts {
//            let i = (s * clampedSegments) / max(1, clampedStruts)
//            points.append(ringPoint(i, z: baseZ))
//            points.append(ringPoint(i, z: topZ))
//        }
//
//        return RenderObject(points: points, color: color, primitive: .lineList)
//    }

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

        return RenderObject(role: .axes, points: points, color: color, primitive: .lineList)
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
//    static func dashedShape(center: SIMD3<Float> = SIMD3<Float>(50, 25, 15),
//                            outerRadius: Float = 22,
//                            innerRadius: Float = 9,
//                            points pointCount: Int = 5,
//                            color: SIMD4<Float> = SIMD4<Float>(1.0, 0.75, 0.1, 1.0),
//                            dashLength: Float = 3.0) -> RenderObject {
//        let spikes = max(3, pointCount)
//        var vertices: [SIMD3<Float>] = []
//        vertices.reserveCapacity(spikes * 2 + 1)
//
//        for i in 0..<(spikes * 2) {
//            let angle = Float(i) * .pi / Float(spikes)
//            let radius = i % 2 == 0 ? outerRadius : innerRadius
//            vertices.append(SIMD3<Float>(center.x + radius * cos(angle),
//                                         center.y + radius * sin(angle),
//                                         center.z))
//        }
//        vertices.append(vertices[0]) // close the loop
//
//        return RenderObject(points: vertices,
//                            color: color,
//                            primitive: .lineStrip,
//                            isDashed: true,
//                            dashLength: dashLength)
//    }

    static func defaultScene() -> [RenderObject] {
        // `stockBox()`'s default bottomZ — the real stock's bottom takes over
        // once `CanvasSceneModel.updateStock` runs.
        let stockBottomZ: Float = -10
        var scene = axes()
        scene.append(.stockBox())
        scene.append(contentsOf: fixtures(bottomZ: stockBottomZ))
        return scene
    }
}
