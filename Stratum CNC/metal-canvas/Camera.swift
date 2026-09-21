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

    /// Which way the camera faces, as a rotation of world space: its
    /// columns are the camera's right, up and back (target → eye) directions
    /// in world coordinates. Identity is the default view — straight down
    /// the Z axis onto the XY plane, X to the right, Y up the screen.
    ///
    /// A quaternion rather than yaw/pitch angles because yaw/pitch around a
    /// fixed up axis can only produce views with world Y up on screen: no
    /// side view could ever have Z (the machine's vertical) pointing up.
    var orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    /// The machine's vertical. Orbiting turns the world around this axis, so
    /// Z stays up on screen (see `preferredTurntableAxis(for:)`).
    static let machineUp = SIMD3<Float>(0, 0, 1)

    /// The world axis `orbit` spins around for horizontal movement.
    /// Vertical movement tilts around the camera's own X axis and stops when
    /// the camera would tip past this axis, so the view never rolls upside
    /// down.
    ///
    /// This is the machine's Z axis, including from the top view. It used to
    /// be the screen's "up" at the moment the view was set — world Y for the
    /// top view — which made every orbit from the top a rotation around Y:
    /// yaw and pitch each moved the camera, but the roll of the result was
    /// then fixed by the two of them, so views with Z up on screen and both
    /// X and Y sides showing (e.g. -X, -Y, +Z) simply couldn't be reached.
    var turntableAxis = Camera.machineUp

    /// Which axis to orbit around for a camera that's facing `q`: the
    /// machine's Z, unless that would be wrong for this pose —
    ///  - upside-down relative to Z: keep the screen's own up, so the view
    ///    stays consistent instead of jumping upright on the first tilt;
    ///  - camera-right parallel to Z (a view rolled onto its side): tilting
    ///    would just spin around Z again and never leave that plane, so
    ///    again use the screen's up.
    /// Every standard view, and everything orbiting from one, gets Z.
    static func preferredTurntableAxis(for q: simd_quatf) -> SIMD3<Float> {
        let screenUp = q.act(SIMD3<Float>(0, 1, 0))
        let screenRight = q.act(SIMD3<Float>(1, 0, 0))
        let upright = simd_dot(screenUp, machineUp) >= -1e-4
        let rolledSideways = abs(simd_dot(screenRight, machineUp)) > 0.999
        return upright && !rolledSideways ? machineUp : screenUp
    }

    var distance: Float = 20.0

    /// The camera's right / up / back (target → eye) directions in world space.
    var right: SIMD3<Float> { orientation.act(SIMD3<Float>(1, 0, 0)) }
    var up: SIMD3<Float> { orientation.act(SIMD3<Float>(0, 1, 0)) }
    var back: SIMD3<Float> { orientation.act(SIMD3<Float>(0, 0, 1)) }

    /// The camera's right/up basis vectors in world space, for the current orientation.
    /// These match the view-space x/y axes computed in `matrix_look_at`.
    private func basisVectors() -> (right: SIMD3<Float>, up: SIMD3<Float>) {
        (right, up)
    }

    /// Turntable orbit: `yaw` spins the scene around `turntableAxis`,
    /// `pitch` tilts it around the camera's own X axis (both in radians).
    ///
    /// From the top view the tilt only goes one way (toward the front) — the
    /// same stop a turntable has at straight-up/straight-down; spin 180° first
    /// to tilt toward the back.
    func orbit(yaw: Float, pitch: Float) {
        var q = orientation
        if yaw != 0 {
            q = simd_mul(simd_quatf(angle: yaw, axis: turntableAxis), q)
        }
        if pitch != 0 {
            // Tilting by φ moves the camera's up vector to
            //   cos φ · up + sin φ · back,
            // so its height along the turntable axis is A·cos φ + B·sin φ.
            // That stays ≥ 0 (camera not upside down) for φ within ±90° of
            // φ0 = atan2(B, A) — clamp to that range, which lands exactly on
            // the straight-up/down pose instead of stopping short of it.
            let a = simd_dot(q.act(SIMD3<Float>(0, 1, 0)), turntableAxis)
            let b = simd_dot(q.act(SIMD3<Float>(0, 0, 1)), turntableAxis)
            var tilt = pitch
            if (a * a + b * b).squareRoot() > 1e-6 {
                let centre = atan2(b, a)
                tilt = min(max(tilt, centre - .pi / 2), centre + .pi / 2)
            }
            q = simd_mul(q, simd_quatf(angle: tilt, axis: SIMD3<Float>(1, 0, 0)))
        }
        // Re-normalize so rounding error from thousands of small rotations
        // can't accumulate into a skewed view.
        orientation = simd_normalize(q)
    }

    /// Jumps to one of the six standard views, keeping the current target
    /// and zoom.
    func snap(to view: StandardView) {
        orientation = view.orientation
        turntableAxis = Camera.preferredTurntableAxis(for: orientation)
    }

    /// Whether the camera is currently squared up on one of the six
    /// axis-aligned standard views, as opposed to some free-orbited angle
    /// in between. `snapToFace(forSwipe:_:)` only takes a 90° step when
    /// this is true — a 90° step from an arbitrary angle wouldn't land on
    /// a face at all, so that's the signal to snap to Top first instead.
    private var isOnAFace: Bool {
        let threshold: Float = 0.999
        return abs(back.x) > threshold || abs(back.y) > threshold || abs(back.z) > threshold
    }

    /// "Snap to Face": tumbles the model exactly 90° toward the direction of
    /// an Option+swipe (see `MetalCanvasView.Coordinator.performViewSnap`),
    /// composed onto whatever the orientation already is.
    ///
    /// From a free orbit the swipe direction is discarded and this snaps
    /// straight to Top — the view the whole scheme is anchored to. The very
    /// next swipe, now starting from a face, takes a real quarter turn. From
    /// Top:
    ///  - swipe up    → the front face (-Y), Z up the screen
    ///  - swipe down  → the back face (+Y), turned over about the screen's X
    ///                  axis, so Z points down the screen — upside down
    ///  - swipe right → the -X face, turned about the screen's Y axis
    ///  - swipe left  → the +X face
    ///
    /// The turns are about the *screen's own* axes — the model follows the
    /// fingers like a trackball — and never about world Z. World Z was
    /// tried for the horizontal swipe, but from Top that just spins the
    /// view in place instead of reaching the X faces. Nothing corrects the
    /// roll afterwards either: the twist a path took to get to a face
    /// carries forward, as when turning a real object over. From a view
    /// with Z up on screen (front, back, left, right) a horizontal swipe
    /// still lands on the next side with Z up.
    ///
    /// Refuses a swipe that would land on the excluded bottom face,
    /// leaving the view unchanged.
    ///
    /// - Parameters:
    ///   - dx: horizontal scroll delta, positive = fingers moving right.
    ///   - dy: vertical scroll delta, positive = fingers moving down.
    func snapToFace(forSwipe dx: Float, _ dy: Float) {
        guard isOnAFace else {
            snap(to: .top)
            return
        }

        // Fingers dragging the surface facing you to the right bring the
        // face on its left side round to face you, i.e. the eye moves to
        // -X: a negative quarter turn about the screen's Y axis. Likewise
        // fingers moving down bring the far (+Y) side round.
        var q = orientation
        if abs(dx) > abs(dy) {
            let angle: Float = dx > 0 ? .pi / 2 : -.pi / 2
            q = simd_mul(q, simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0)))
        } else {
            let angle: Float = dy > 0 ? .pi / 2 : -.pi / 2
            q = simd_mul(q, simd_quatf(angle: angle, axis: SIMD3<Float>(1, 0, 0)))
        }
        q = simd_normalize(q)

        // Refuse to land on the excluded bottom face.
        let newBack = q.act(SIMD3<Float>(0, 0, 1))
        guard simd_dot(newBack, SIMD3<Float>(0, 0, -1)) < 0.99 else {
            return
        }

        orientation = q
        turntableAxis = Camera.preferredTurntableAxis(for: q)
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

    /// The inverse of what `zoom(to:towards:)` does inline: the world point
    /// that sits under `ndc` on screen, on the plane `z == planeZ` (the
    /// default, z = 0, is where all of CAM's geometry lives).
    ///
    /// The projection is orthographic, so every screen point is a ray
    /// parallel to the view direction; this finds the point on the focal
    /// plane under `ndc`, then slides it along that direction until it
    /// reaches `planeZ`. From the top view that's just `target` plus the
    /// screen offset; from a side view (`back.z == 0`) the ray never meets
    /// the plane and this returns `nil`.
    /// - Parameter ndc: same convention as `zoom(to:towards:)` — -1...1,
    ///   (0,0) the screen center, +1 right/top.
    func worldPoint(atScreenNDC ndc: SIMD2<Float>, planeZ: Float = 0) -> SIMD3<Float>? {
        let halfHeight = distance * tan(fov * 0.5)
        let halfWidth = halfHeight * aspectRatio

        let onFocalPlane = target + right * (ndc.x * halfWidth) + up * (ndc.y * halfHeight)

        let backZ = back.z
        guard abs(backZ) > 1e-6 else {
            return nil
        }
        let slide = (onFocalPlane.z - planeZ) / backZ
        return onFocalPlane - back * slide
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
        let eye = target + back * Self.viewStandoff
        let view = matrix_look_at(eye: eye, target: target, up: up)

        let halfHeight = distance * tan(fov * 0.5)
        let halfWidth = halfHeight * aspectRatio

        let proj = matrix_orthographic(left: -halfWidth, right: halfWidth,
                                       bottom: -halfHeight, top: halfHeight,
                                       nearZ: nearZ, farZ: Self.viewStandoff * 2)

        return simd_mul(proj, view)
    }

    /// MVP for the orientation cube (see `OrientationCube` and
    /// `MetalRenderer.drawOrientationCube`): only the camera's *rotation*,
    /// none of its target/zoom, so the cube sits still in its corner and
    /// just turns the way the world turns.
    ///
    /// The rotation part is the same one `matrix_look_at` builds — its rows
    /// are the camera's right/up/back in world space, so a world direction
    /// comes out as (right·v, up·v, back·v) — followed by a fixed push
    /// `distance` in front of the camera and a square orthographic
    /// projection. `halfExtent` is the half-size of the visible square in
    /// cube units; it has to exceed the cube's corner radius (√3 ≈ 1.73 for
    /// a cube of half-size 1) or corners get clipped at some angles.
    func orientationCubeMatrix(halfExtent: Float, distance: Float = 5) -> matrix_float4x4 {
        let r = right
        let u = up
        let b = back
        let rotationAndPush = matrix_float4x4(
            SIMD4<Float>(r.x, u.x, b.x, 0),
            SIMD4<Float>(r.y, u.y, b.y, 0),
            SIMD4<Float>(r.z, u.z, b.z, 0),
            SIMD4<Float>(0, 0, -distance, 1)
        )
        let proj = matrix_orthographic(left: -halfExtent, right: halfExtent,
                                       bottom: -halfExtent, top: halfExtent,
                                       nearZ: distance - 2.5, farZ: distance + 2.5)
        return simd_mul(proj, rotationAndPush)
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
