//
//  D2.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//


//
//  D2_RenderObjectBuilder.swift
//  Stratum CNC
//
//  Converts CAM's vector data — `D2_Object`'s Bezier paths, and
//  `D2_CanvasState.toolpathsPath` — into `RenderObject`s the Metal canvas
//  can draw. This is the "B"/"C" workstream of the plan to reuse
//  `MetalCanvasView` in CAM instead of `CAM_2D_View`'s CoreAnimation stack:
//  pure, view-free functions. Feed one a `D2_CanvasState` snapshot, get
//  `[RenderObject]` (plus, per path, the world-space `CGPath` a future hit
//  tester needs — see `D2_RenderPath.worldPath`) back out. Nothing here
//  touches `D2_CanvasNSView`, `D2_ObjectNode` or any SwiftUI view — those
//  are follow-up steps once this is wired into an actual Metal-backed CAM
//  view.
//

import AppKit
import CoreGraphics

/// One CAM vector path's rendering + hit-testing data, built together in a
/// single flatten pass so a future hit tester (the plan's "D" workstream,
/// not built yet) never has to redo the Bezier → world-space transform
/// this already did.
struct D2_RenderPath {
    /// Which `D2_Object` this came from.
    let objectID: UUID
    /// Index into `object.paths` — resolves 1:1 to a `PathSelection`.
    let pathIndex: Int
    /// Ready to hand to `MetalCanvasView` (via `objects.append`/similar).
    /// A fresh `RenderObject` — and so a fresh `RenderObject.id` — every
    /// time this builder runs: `RenderObject.id`'s `UUID()` default is
    /// evaluated per-instance, not once, so a path that's just been
    /// selected/deselected/picked (a new `color`, same points) naturally
    /// gets a new id and a rebuilt GPU buffer. `MetalRenderer.updateGeometry`
    /// only reuses a buffer when the id is *unchanged* — recoloring a path
    /// without minting a new id would silently leave the old color on
    /// screen. See the plan's "C" workstream note on this.
    let renderObject: RenderObject
    /// The same flattened, world-space polyline `renderObject.points` was
    /// built from, as a `CGPath` — what a ported `PathHitTester` will run
    /// `copy(strokingWithWidth:...).contains(point)` against, in world
    /// coordinates instead of `D2_ObjectNode`'s per-node local space.
    let worldPath: CGPath
    /// World-space bounding box of `worldPath` — for a hit test's cheap
    /// early-out, the same role `PathHitTester.hitTest`'s
    /// `hitBounds.contains(localPoint)` check plays today.
    let worldBounds: CGRect
}

enum D2_RenderObjectBuilder {

    /// Flattening tolerance in mm — matches `BezierPathFlattener`'s own
    /// default. CAM draws at 1:1 mm scale, so this stays sub-pixel at any
    /// zoom level someone actually works at.
    static let flattenTolerance: CGFloat = 0.1

    // MARK: Vector objects

    /// Every path of every object in `state`, colored for its current
    /// selection/picking state. The whole scene's vector geometry, in one
    /// call.
    static func renderPaths(for state: D2_CanvasState) -> [D2_RenderPath] {
        state.objects.flatMap { object in
            renderPaths(for: object,
                       objectSelected: state.selectedObjectIDs.contains(object.id),
                       selectedPathIndexes: state.selectedPathIndices(for: object),
                       pickedPathIndexes: state.pickedPathIndices(for: object))
        }
    }

    /// One `D2_RenderPath` per `object.paths[i]` — never one per object —
    /// so each path carries its own selection color and a hit resolves
    /// straight to a `pathIndex`. Mirrors how `D2_ObjectNode.updateStyles`
    /// colors its per-path `shapeLayers` today.
    static func renderPaths(for object: D2_Object,
                            objectSelected: Bool,
                            selectedPathIndexes: Set<Int>,
                            pickedPathIndexes: Set<Int>) -> [D2_RenderPath] {

        object.paths.indices.map { index in
            renderPath(for: object,
                      pathIndex: index,
                      color: color(objectSelected: objectSelected,
                                   pathSelected: selectedPathIndexes.contains(index),
                                   picked: pickedPathIndexes.contains(index)))
        }
    }

    private static func renderPath(for object: D2_Object, pathIndex: Int, color: SIMD4<Float>) -> D2_RenderPath {
        let localSubpaths = flattenedSubpaths(object.paths[pathIndex].cgPath)

        // Map every flattened vertex into world space with the object's
        // *current* position/scale/rotation — the same rule
        // `D2_Object.machineEntities`/`machineContours(forPathAt:)` follow,
        // so what's drawn always matches what would actually get machined.
        let worldSubpaths = localSubpaths.map { subpath in
            subpath.map { object.worldPoint(fromLocal: $0) }
        }

        return makeRenderPath(objectID: object.id, pathIndex: pathIndex,
                              worldSubpaths: worldSubpaths, color: color)
    }

    /// Same precedence `D2_ObjectNode.updateStyles` uses: picked beats
    /// object-selected beats path-selected beats the default label color.
    private static func color(objectSelected: Bool, pathSelected: Bool, picked: Bool) -> SIMD4<Float> {
        if picked {
            return STColor.systemOrange.simd4RGBA
        } else if objectSelected {
            return STColor.systemRed.simd4RGBA
        } else if pathSelected {
            return STColor.systemBlue.simd4RGBA
        } else {
            return STColor.labelColor.simd4RGBA
        }
    }

    // MARK: Toolpath preview

    /// `state.toolpathsPath` as one `RenderObject`, or `nil` if nothing's
    /// been generated yet. Already in world coordinates and already
    /// straight-chord-approximated by `ToolpathPathBuilder` (arcs included
    /// — see its `chordTolerance`), so there are no Bezier curves left to
    /// flatten; `flattenedSubpaths` is still run for uniformity, but it's a
    /// no-op pass-through on path data that's already all `moveTo`/`lineTo`.
    static func toolpathRenderObject(for state: D2_CanvasState,
                                     color: SIMD4<Float> = SIMD4<Float>(0.2, 0.5, 1.0, 1.0)) -> RenderObject? {
        guard let path = state.toolpathsPath else {
            return nil
        }
        let subpaths = flattenedSubpaths(path)
        let simdSubpaths = subpaths.map { subpath in
            subpath.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) }
        }
        return lineListObject(from: simdSubpaths, color: color)
    }

    // MARK: Shared geometry helpers

    /// Splits `path` into subpaths and flattens any curves in each to a
    /// polyline, via `NSBezierPath(cgPath:)` + the existing (already
    /// battle-tested for G-code toolpath rendering) `BezierPathFlattener`
    /// — reused rather than re-implemented. A path with no curves (the
    /// toolpath preview) flattens to itself at negligible cost.
    private static func flattenedSubpaths(_ path: CGPath) -> [[CGPoint]] {
        BezierPathFlattener.flatten([NSBezierPath(cgPath: path)], tolerance: flattenTolerance)
    }

    /// Builds a `.lineList` `RenderObject` from one or more world-space
    /// polylines — consecutive point pairs, never one continuous
    /// `.lineStrip`. That matters whenever a path has more than one
    /// subpath (e.g. a letter "O"'s outer and inner ring both live in one
    /// `object.paths[i]`, per `D2_Object`'s own doc comment on `contours`):
    /// a single `.lineStrip` across subpaths would draw a spurious line
    /// connecting one subpath's last point to the next one's first.
    private static func lineListObject(from subpaths: [[SIMD3<Float>]], color: SIMD4<Float>) -> RenderObject? {
        var points: [SIMD3<Float>] = []
        for subpath in subpaths where subpath.count > 1 {
            for i in 0..<(subpath.count - 1) {
                points.append(subpath[i])
                points.append(subpath[i + 1])
            }
        }
        guard !points.isEmpty else {
            return nil
        }
        return RenderObject(points: points, color: color, primitive: .lineList)
    }

    private static func makeRenderPath(objectID: UUID, pathIndex: Int,
                                       worldSubpaths: [[CGPoint]], color: SIMD4<Float>) -> D2_RenderPath {

        let simdSubpaths = worldSubpaths.map { subpath in
            subpath.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) }
        }
        // A path with no visible geometry (shouldn't happen in practice —
        // every `D2_Object.paths` entry comes from a real imported shape —
        // but kept safe rather than force-unwrapping) still needs a
        // `D2_RenderPath` so its index lines up with `object.paths`; it
        // just draws and hit-tests nothing.
        let object = lineListObject(from: simdSubpaths, color: color)
            ?? RenderObject(points: [], color: color, primitive: .lineList)

        let mutablePath = CGMutablePath()
        for subpath in worldSubpaths where !subpath.isEmpty {
            mutablePath.move(to: subpath[0])
            for point in subpath.dropFirst() {
                mutablePath.addLine(to: point)
            }
        }

        return D2_RenderPath(objectID: objectID, pathIndex: pathIndex,
                            renderObject: object, worldPath: mutablePath,
                            worldBounds: mutablePath.boundingBoxOfPath)
    }
}

private extension STColor {
    /// RGBA in the space `RenderVertex.color` expects. Goes through
    /// `cgColor` — which every other use of `STColor` in `renderer-2D`
    /// already relies on — rather than assuming `STColor` is itself an
    /// `NSColor` with `redComponent`/`greenComponent`/etc, so this works
    /// whichever concrete type `STColor` turns out to be. Dynamic system
    /// colors (`.labelColor` etc.) resolve against whatever appearance is
    /// current when this runs, same as `.cgColor` already does implicitly
    /// everywhere else.
    var simd4RGBA: SIMD4<Float> {
        let color = cgColor
        if let converted = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
           let components = converted.components, components.count >= 4 {
            return SIMD4<Float>(Float(components[0]), Float(components[1]),
                                Float(components[2]), Float(components[3]))
        }
        // Grayscale/other color spaces without 4 components — approximate
        // as a gray with whatever alpha is present.
        if let components = color.components, let white = components.first {
            let alpha = components.count > 1 ? components[1] : 1
            return SIMD4<Float>(Float(white), Float(white), Float(white), Float(alpha))
        }
        return SIMD4<Float>(1, 1, 1, 1)
    }
}