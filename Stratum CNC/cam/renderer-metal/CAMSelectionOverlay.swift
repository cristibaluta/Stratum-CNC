//
//  CAMSelectionOverlay.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  What `D2_ObjectNode` draws on top of a selected object — the dashed
//  bounding box and the rotation-center handle — as `RenderObject`s. The
//  handle isn't decoration: it's the grab point for drag-to-move (see
//  `CAMCanvasInteraction`), so it has to exist in the Metal view for that
//  interaction to be discoverable at all.
//
//  Both are placed through `D2_Object.worldPoint(fromLocal:)`, the same
//  mapping the shapes themselves go through, so they stay glued to the
//  object however it's moved, scaled or rotated.
//

import Foundation
import CoreGraphics

enum CAMSelectionOverlay {

    /// Dash length in world mm (Metal dashes are on/off runs of this length).
    /// `D2_ObjectNode` uses a [6, 4] pattern in object-local units; a fixed
    /// world length is close enough for now — visual parity is step 5.
    static let dashLength: Float = 3

    // Same numbers as `CenterShapeLayer`, in the object's local units, so
    // the handle scales with the object exactly as it does today.
    private static let handleRadius: CGFloat = 3.5
    private static let handleCrossSize: CGFloat = 7
    private static let handleSegments = 24

    /// Dashed box + handle for one selected object. Handle first: with all
    /// of this at z = 0, the first-drawn line wins where two coincide, and
    /// the handle should be on top.
    static func renderObjects(for object: D2_Object,
                              boxColor: SIMD4<Float>,
                              handleColor: SIMD4<Float>) -> [RenderObject] {
        [rotationHandle(for: object, color: handleColor),
         selectionBox(for: object, color: boxColor)]
    }

    private static func selectionBox(for object: D2_Object, color: SIMD4<Float>) -> RenderObject {
        let w = object.originalSize.width
        let h = object.originalSize.height
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
                       CGPoint(x: w, y: h), CGPoint(x: 0, y: h),
                       CGPoint(x: 0, y: 0)]
        return RenderObject(points: corners.map { simd(object.worldPoint(fromLocal: $0)) },
                            color: color,
                            primitive: .lineStrip,
                            isDashed: true,
                            dashLength: dashLength)
    }

    /// A ring plus a cross, as disconnected segments. Hairlines only, so no
    /// filled dot like the CoreAnimation one — QA item.
    private static func rotationHandle(for object: D2_Object, color: SIMD4<Float>) -> RenderObject {
        let cx = object.originalSize.width / 2
        let cy = object.originalSize.height / 2

        func local(_ dx: CGFloat, _ dy: CGFloat) -> SIMD3<Float> {
            simd(object.worldPoint(fromLocal: CGPoint(x: cx + dx, y: cy + dy)))
        }

        var points: [SIMD3<Float>] = []

        for i in 0..<handleSegments {
            let a0 = CGFloat(i) / CGFloat(handleSegments) * 2 * .pi
            let a1 = CGFloat(i + 1) / CGFloat(handleSegments) * 2 * .pi
            points.append(local(handleRadius * cos(a0), handleRadius * sin(a0)))
            points.append(local(handleRadius * cos(a1), handleRadius * sin(a1)))
        }

        points.append(local(-handleCrossSize, 0))
        points.append(local(handleCrossSize, 0))
        points.append(local(0, -handleCrossSize))
        points.append(local(0, handleCrossSize))

        return RenderObject(points: points, color: color, primitive: .lineList)
    }

    private static func simd(_ point: CGPoint) -> SIMD3<Float> {
        SIMD3<Float>(Float(point.x), Float(point.y), 0)
    }
}

/// What the toolpath scrubber puts on the canvas: the part of the toolpath cut
/// so far, and the cutter where it is.
enum CAMToolpathScrubOverlay {

    /// Same blue as the all-toolpaths preview (`D2_RenderObjectBuilder.toolpathRenderObject`).
    private static let pathColor = SIMD4<Float>(0.2, 0.5, 1.0, 1.0)
    /// Same red as the controller's cutter.
    private static let markerColor = SIMD4<Float>(0.9, 0.1, 0.1, 1.0)
    private static let markerSegments = 32

    /// The whole toolpath; the scrubber narrows what is drawn with
    /// `visibleVertexCount`, so this is built once per generation.
    /// Role `.toolpathCutting` is how the scene's fast path finds it again.
    static func pathObject(for data: ToolpathScrubData) -> RenderObject {
        RenderObject(role: .toolpathCutting, points: data.points, color: pathColor, primitive: .lineList)
    }

    /// The cutter seen from above: a ring of the tool's diameter and a cross
    /// through its center. Role `.tool`, so the fast path swaps it in place.
    static func marker(at position: SIMD2<Float>, diameter: Double) -> RenderObject {
        // A hair-thin tool would vanish at any zoom
        let radius = max(Float(max(diameter, 0) / 2), 0.25)

        func point(_ dx: Float, _ dy: Float) -> SIMD3<Float> {
            SIMD3<Float>(position.x + dx, position.y + dy, 0)
        }

        var points: [SIMD3<Float>] = []
        points.reserveCapacity(markerSegments * 2 + 4)
        for i in 0..<markerSegments {
            let a0 = Float(i) / Float(markerSegments) * 2 * .pi
            let a1 = Float(i + 1) / Float(markerSegments) * 2 * .pi
            points.append(point(radius * cos(a0), radius * sin(a0)))
            points.append(point(radius * cos(a1), radius * sin(a1)))
        }
        points.append(point(-radius, 0))
        points.append(point(radius, 0))
        points.append(point(0, -radius))
        points.append(point(0, radius))

        return RenderObject(role: .tool, points: points, color: markerColor, primitive: .lineList)
    }
}
