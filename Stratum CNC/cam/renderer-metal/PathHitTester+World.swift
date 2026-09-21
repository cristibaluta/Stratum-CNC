//
//  PathHitTester+World.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  The plan's "D": hit testing against world-space paths. Same test as the
//  CoreAnimation version — stroke the path a tolerance wide, ask whether it
//  contains the click — but the click no longer has to be converted into
//  each node's local layer space first. `D2_RenderPath.worldPath` is
//  already in world space, built in the same pass as the pixels on screen,
//  so what you can click is exactly what's drawn.
//
//  The layer-based overload in PathHitTester.swift stays until step 6 (it's
//  still what `CAM_2D_View` uses).
//

import Foundation
import CoreGraphics

extension PathHitTester {

    /// - Parameters:
    ///   - worldPoint: the click, in world coordinates.
    ///   - paths: `D2_RenderObjectBuilder.renderPaths(for:)` output, in
    ///     draw order — objects in list order, each object's paths by index.
    ///   - pointsPerWorldUnit: current zoom. `tolerance` is in screen
    ///     points (so a hairline is as easy to hit zoomed out as in), and
    ///     is divided by this to get the world-space reach.
    /// - Returns: the topmost path within reach — later objects and later
    ///   paths win, as they do when drawn on top of each other.
    func hitTest(worldPoint: CGPoint,
                 paths: [D2_RenderPath],
                 pointsPerWorldUnit: CGFloat) -> PathSelection? {

        let worldTolerance = tolerance / max(pointsPerWorldUnit, 0.000001)

        for path in paths.reversed() {

            // Cheap reject first, like the old `hitBounds.contains`.
            let hitBounds = path.worldBounds.insetBy(dx: -worldTolerance, dy: -worldTolerance)
            guard hitBounds.contains(worldPoint) else {
                continue
            }

            let strokedPath = path.worldPath.copy(strokingWithWidth: max(worldTolerance * 2, 0.0001),
                                                  lineCap: .round,
                                                  lineJoin: .round,
                                                  miterLimit: 10)

            if strokedPath.contains(worldPoint) {
                return PathSelection(objectID: path.objectID, pathIndex: path.pathIndex)
            }
        }

        return nil
    }
}
