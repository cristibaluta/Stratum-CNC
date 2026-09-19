//
//  StandardView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 19.09.2026.
//


//
//  StandardView.swift
//  Stratum CNC
//
//  The six axis-aligned views, e.g. for `Camera.snap(to:)`. Option + swipe
//  ("Snap to Face" — see `Camera.snapToFace(forSwipe:_:)` and
//  `MetalCanvasView.Coordinator.performViewSnap`) is a separate, composed
//  rotation that only ever reaches five of these — top, front, back, left,
//  right — deliberately leaving `.bottom` out of reach.
//

import Foundation
import simd

/// World axes: X to the machine's right, Y toward the back, Z up. Same
/// conventions as Blender's numpad views, so they'll look familiar:
/// the four sides have Z pointing up the screen, and Bottom is Top flipped
/// over about the X axis.
enum StandardView: CaseIterable {
    case top
    case bottom
    case front
    case back
    case left
    case right

    /// Direction from the target toward the camera.
    var eye: SIMD3<Float> {
        switch self {
        case .top: SIMD3(0, 0, 1)
        case .bottom: SIMD3(0, 0, -1)
        case .front: SIMD3(0, -1, 0)
        case .back: SIMD3(0, 1, 0)
        case .left: SIMD3(-1, 0, 0)
        case .right: SIMD3(1, 0, 0)
        }
    }

    /// World direction that points up the screen in this view.
    var up: SIMD3<Float> {
        switch self {
        case .top: SIMD3(0, 1, 0)
        case .bottom: SIMD3(0, -1, 0)
        case .front, .back, .left, .right: SIMD3(0, 0, 1)
        }
    }

    /// `Camera.orientation` for this view: a rotation whose columns are the
    /// screen's right, up and back directions.
    var orientation: simd_quatf {
        let back = eye
        let right = simd_normalize(simd_cross(up, back))
        let screenUp = simd_cross(back, right)
        return simd_quatf(simd_float3x3(columns: (right, screenUp, back)))
    }
}