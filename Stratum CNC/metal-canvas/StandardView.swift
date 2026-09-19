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
//  The six axis-aligned views the canvas can snap to (Option + swipe — see
//  `MetalCanvasView.Coordinator.performViewSnap`), and which one a swipe
//  leads to.
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

extension Camera {

    /// The standard view a swipe leads to: the face of the model on the side
    /// of the screen the swipe points toward. Fingers moving right bring up
    /// the view from the screen's right, down from the bottom, and so on.
    ///
    /// That's the same direction Shift + scroll (orbit) already moves the
    /// camera for the same swipe, so the two feel alike; and because it's
    /// worked out from the camera's current right/up, it stays consistent
    /// from every view, and from a tilted one it picks the closest face.
    ///
    /// - Parameters:
    ///   - dx: horizontal scroll delta, positive = fingers moving right.
    ///   - dy: vertical scroll delta, positive = fingers moving down.
    func standardView(forSwipe dx: Float, _ dy: Float) -> StandardView {
        let direction: SIMD3<Float>
        if abs(dx) > abs(dy) {
            direction = dx > 0 ? right : -right
        } else {
            direction = dy > 0 ? -up : up
        }
        return StandardView.allCases.max {
            simd_dot($0.eye, direction) < simd_dot($1.eye, direction)
        } ?? .top
    }
}