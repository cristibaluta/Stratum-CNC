//
//  Uniforms.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 16.09.2026.
//

import Foundation
import simd

struct Uniforms {
    var modelViewProjectionMatrix: matrix_float4x4
    var dashLength: Float
}

class Camera {
    var position: SIMD3<Float> = [0, 0, 150]
    var target: SIMD3<Float> = [0, 0, 0]
    var up: SIMD3<Float> = [0, 1, 0]

    var fov: Float = 90.0 * (.pi / 180.0)
    var aspectRatio: Float = 1.0
    var nearZ: Float = 0.1
    var farZ: Float = 2000.0

    // Default 3D View Angle
    // Pitch (X-axis): -0.6 radians (~-35° looking down)
    // Yaw (Y-axis): 0.8 radians (~45° angled horizontally)
    var rotation: SIMD2<Float> = [0.0, 0.0]

    var distance: Float = 20.0

    func updateMatrix() -> matrix_float4x4 {
        let pitch = simd_quaternion(rotation.x, SIMD3<Float>(1, 0, 0))
        let yaw = simd_quaternion(rotation.y, SIMD3<Float>(0, 1, 0))
        let rotDict = simd_mul(yaw, pitch)

        let eye = target + simd_act(rotDict, SIMD3<Float>(0, 0, distance))
        let view = matrix_look_at(eye: eye, target: target, up: up)

        // Orthographic rather than perspective: toolpaths are precise geometry the
        // user is trying to read dimensions/alignment off of, and perspective's
        // foreshortening makes a square look trapezoidal and two parallel toolpath
        // passes look non-parallel the moment the camera isn't dead-on. Orthographic
        // keeps parallel lines parallel and true lengths true at any orbit angle.
        //
        // The view's half-height is tied to `distance` (via the old perspective
        // `fov`) purely so scroll-to-zoom keeps behaving the way it already does --
        // objects at the target plane are still the same apparent size they'd have
        // been under perspective at this same distance, so zooming still feels
        // continuous across the switch rather than jumping in scale.
        let halfHeight = distance * tan(fov * 0.5)
        let halfWidth = halfHeight * aspectRatio
        let proj = matrix_orthographic(left: -halfWidth, right: halfWidth,
                                       bottom: -halfHeight, top: halfHeight,
                                       nearZ: nearZ, farZ: farZ)

        return simd_mul(proj, view)
    }

    private func matrix_look_at(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)

        let t = SIMD3<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye))

        return matrix_float4x4(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        )
    }

    /// Kept alongside `matrix_orthographic` (unused by `updateMatrix()` now) in case
    /// a perspective toggle is ever wanted again -- swapping the call in
    /// `updateMatrix()` is then a one-line change instead of rewriting this.
    private func matrix_perspective(fovY: Float, aspect: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
        let yScale = 1 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zScale = farZ / (nearZ - farZ)
        let zOffset = (nearZ * farZ) / (nearZ - farZ)

        return matrix_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, zOffset, 0)
        )
    }

    /// Standard symmetric-frustum orthographic projection into Metal's [0, 1] depth
    /// range (matching `matrix_perspective`'s own convention above): unlike
    /// perspective there's no `w` divide, so parallel lines in view space stay
    /// parallel on screen regardless of orbit angle or distance from the target.
    private func matrix_orthographic(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
        let xScale = 2 / (right - left)
        let yScale = 2 / (top - bottom)
        let zScale = 1 / (farZ - nearZ)
        let xOffset = -(right + left) / (right - left)
        let yOffset = -(top + bottom) / (top - bottom)
        let zOffset = -nearZ * zScale

        return matrix_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, -zScale, 0),
            SIMD4<Float>(xOffset, yOffset, zOffset, 1)
        )
    }
}
