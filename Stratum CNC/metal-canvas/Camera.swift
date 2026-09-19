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
    /// XY offset applied to vertex position in model space, before the MVP
    /// transform — mirrors `CanvasSceneModel.xyOffset`. Zero for every batch
    /// except `.toolpathRapid`/`.toolpathCutting` (see `MetalRenderer.drawBatch`);
    /// everything else (stock box, tool marker, axes) always passes `.zero`
    /// here so it stays put while the toolpath preview shifts.
    var offset: SIMD2<Float> = .zero
}

class Camera {
    var position: SIMD3<Float> = [0, 0, 150]
    var target: SIMD3<Float> = [0, 0, 0]
    var up: SIMD3<Float> = [0, 1, 0]

    var fov: Float = 90.0 * (.pi / 180.0)
    var aspectRatio: Float = 1.0
    var nearZ: Float = 0.1
    var farZ: Float = 2000.0

    /// Fixed eye-to-target distance used for the view/clip volume (see
    /// `updateMatrix`). Visible depth is `target ± viewStandoff` along the
    /// view direction — comfortably more than any job on the machine.
    /// Depth is linear in an orthographic projection, so a longer range
    /// costs no precision to speak of.
    private static let viewStandoff: Float = 1000.0

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

    /// Slides `target` in the view plane so the scene follows the pointer
    /// 1:1 on screen, at any zoom level.
    /// - Parameters:
    ///   - translation: pointer/scroll movement in view points (x right, y
    ///     in the same sign convention the caller already uses).
    ///   - viewportHeight: height of the view in the same points.
    func pan(by translation: SIMD2<Float>, viewportHeight: Float) {
        // The view spans `2 * distance * tan(fov/2)` world units vertically
        // (orthographic — see `updateMatrix`), so one point on screen is
        // that divided by the viewport height. Scaling by this rather than
        // a constant is what keeps the pan speed independent of zoom.
        let worldPerPoint = 2 * distance * tan(fov * 0.5) / viewportHeight
        let (right, camUp) = basisVectors()
        target -= right * (translation.x * worldPerPoint)
                + camUp * (translation.y * worldPerPoint)
    }

    func updateMatrix() -> matrix_float4x4 {
        let pitch = simd_quaternion(rotation.x, SIMD3<Float>(1, 0, 0))
        let yaw = simd_quaternion(rotation.y, SIMD3<Float>(0, 1, 0))
        let rotDict = simd_mul(yaw, pitch)

        // The projection is orthographic, so `distance` only sets the zoom
        // (via the half extents below) — it has no effect on how big things
        // look. The eye's real distance from `target` only decides which
        // slice of depth survives clipping, and tying it to the zoom level
        // was the bug: zoomed in to a few mm, everything more than that far
        // toward the camera from `target` — the near side of the scene once
        // it's tilted, i.e. center-of-screen to bottom — fell behind the
        // near plane and vanished. So the eye sits at a fixed standoff and
        // the clip range is centered on `target`: `viewStandoff` of depth
        // either side of it.
        let eye = target + simd_act(rotDict, SIMD3<Float>(0, 0, Self.viewStandoff))
        let view = matrix_look_at(eye: eye, target: target, up: up)

        let halfHeight = distance * tan(fov * 0.5)
        let halfWidth = halfHeight * aspectRatio

        let proj = matrix_orthographic(left: -halfWidth, right: halfWidth,
                                       bottom: -halfHeight, top: halfHeight,
                                       nearZ: nearZ, farZ: Self.viewStandoff * 2)

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
