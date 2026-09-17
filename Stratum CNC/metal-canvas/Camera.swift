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

    /// The camera's right/up basis vectors in world space, for the current rotation.
    /// These match the view-space x/y axes computed in `matrix_look_at`.
    private func basisVectors() -> (right: SIMD3<Float>, up: SIMD3<Float>) {
        let pitch = simd_quaternion(rotation.x, SIMD3<Float>(1, 0, 0))
        let yaw = simd_quaternion(rotation.y, SIMD3<Float>(0, 1, 0))
        let rotDict = simd_mul(yaw, pitch)

        let eye = target + simd_act(rotDict, SIMD3<Float>(0, 0, distance))
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        return (x, y)
    }

    /// Changes `distance` (zoom level) while keeping the world point currently under
    /// `ndc` fixed on screen, instead of zooming around `target`.
    /// - Parameter ndc: screen position in normalized device coords, -1...1,
    ///   where (0,0) is the screen center, +1 is right/top.
    func zoom(to newDistance: Float, towards ndc: SIMD2<Float>) {
        let oldHalfHeight = distance * tan(fov * 0.5)
        let oldHalfWidth = oldHalfHeight * aspectRatio

        let newHalfHeight = newDistance * tan(fov * 0.5)
        let newHalfWidth = newHalfHeight * aspectRatio

        let (right, camUp) = basisVectors()
        target += right * (ndc.x * (oldHalfWidth - newHalfWidth))
                + camUp * (ndc.y * (oldHalfHeight - newHalfHeight))

        distance = newDistance
    }

    func updateMatrix() -> matrix_float4x4 {
        let pitch = simd_quaternion(rotation.x, SIMD3<Float>(1, 0, 0))
        let yaw = simd_quaternion(rotation.y, SIMD3<Float>(0, 1, 0))
        let rotDict = simd_mul(yaw, pitch)

        let eye = target + simd_act(rotDict, SIMD3<Float>(0, 0, distance))
        let view = matrix_look_at(eye: eye, target: target, up: up)

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
