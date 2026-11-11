//
//  STEPOrientation.swift
//  Stratum CNC
//
//  Which face of an imported STEP model faces up. A CAD file has its own idea of "up", which is
//  often not the side the part is cut from, so the user picks the face. The faces are the ones of
//  `SetupFace`, named in the model's own frame as `Setup.swift` has them:
//
//      face     the model's own direction that ends up facing up
//      top      +Z   (as imported)
//      bottom   −Z   (flipped over about X)
//      front    −Y   (the side toward the operator)
//      back     +Y
//      left     −X
//      right    +X
//
//  A side face is turned about the horizontal axis that reaches it, so the part is not also spun
//  about the vertical axis. After the turn the model is put back like a fresh import: its corner
//  (min X, min Y) at x0 y0 and its top (max Z) at z0.
//
//  Each body of a file is turned (and scaled) on its own, about its own corner.
//

import Foundation
import simd

extension SetupFace {

    /// Rotation that brings this face of the model to the top.
    var modelRotation: simd_float3x3 {
        // Columns: where the model's X, Y and Z axes end up.
        switch self {
            case .top:
                return matrix_identity_float3x3
            case .bottom:   // (x, y, z) -> (x, -y, -z)
                return simd_float3x3(columns: ([1, 0, 0], [0, -1, 0], [0, 0, -1]))
            case .front:    // (x, y, z) -> (x, z, -y)
                return simd_float3x3(columns: ([1, 0, 0], [0, 0, -1], [0, 1, 0]))
            case .back:     // (x, y, z) -> (x, -z, y)
                return simd_float3x3(columns: ([1, 0, 0], [0, 0, 1], [0, -1, 0]))
            case .left:     // (x, y, z) -> (z, y, -x)
                return simd_float3x3(columns: ([0, 0, -1], [0, 1, 0], [1, 0, 0]))
            case .right:    // (x, y, z) -> (-z, y, x)
                return simd_float3x3(columns: ([0, 0, 1], [0, 1, 0], [-1, 0, 0]))
        }
    }
}

/// How one body of an imported file was moved, scaled and turned to sit in its own frame: applied
/// to anything that is still in the file's frame, i.e. the surface meshes. The meshes are measured
/// from the whole file's origin; a body's edges are already in its own frame (`STEPDisplayGeometry`).
///
///     point(p) = rotation * ((p + anchor) * scale) + shift
///
/// `anchor` takes a mesh position to the body's own frame (corner at x0 y0, top at z0), `scale` and
/// `rotation` act about that corner, and `shift` puts the turned body back on it.
struct STEPPlacement: Sendable {
    let rotation: simd_float3x3
    let shift: SIMD3<Float>
    let anchor: SIMD3<Float>
    let scale: Float
    /// Nothing to apply, so the original data can be used as it is.
    let isIdentity: Bool

    static let identity = STEPPlacement(rotation: matrix_identity_float3x3, shift: .zero)

    init(rotation: simd_float3x3, shift: SIMD3<Float>, anchor: SIMD3<Float> = .zero, scale: Float = 1) {
        self.rotation = rotation
        self.shift = shift
        self.anchor = anchor
        self.scale = scale
        isIdentity = rotation.columns.0 == SIMD3<Float>(1, 0, 0)
            && rotation.columns.1 == SIMD3<Float>(0, 1, 0)
            && rotation.columns.2 == SIMD3<Float>(0, 0, 1)
            && shift == .zero && anchor == .zero && scale == 1
    }

    func point(_ p: SIMD3<Float>) -> SIMD3<Float> { rotation * ((p + anchor) * scale) + shift }

    /// Directions (normals) only turn. (A uniform scale leaves a unit direction as it is.)
    func direction(_ d: SIMD3<Float>) -> SIMD3<Float> { rotation * d }
}

extension STEPDisplayGeometry {

    init(origin: SIMD3<Double>, bodies: [Body]) {
        self.origin = origin
        self.bodies = bodies
    }
}

extension STEPDisplayGeometry.Body {

    /// The same edges scaled by `scale` and turned by `rotation`, both about the body's corner, and
    /// moved back to it: min X and min Y at 0, max Z at 0. Edge ids and point order are unchanged.
    /// `shift` is the move that put it back, for `STEPPlacement`.
    func placed(rotation: simd_float3x3, scale: Float) -> (body: STEPDisplayGeometry.Body, shift: SIMD3<Float>) {
        var low = SIMD3<Float>(repeating: .infinity)
        var high = SIMD3<Float>(repeating: -.infinity)
        let turned = points.map { rotation * ($0 * scale) }
        for point in turned {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        guard low.x.isFinite, low.y.isFinite, high.z.isFinite else { return (self, .zero) }

        let shift = SIMD3<Float>(-low.x, -low.y, -high.z)
        let moved = STEPDisplayGeometry.Body(id: id, points: turned.map { $0 + shift }, edges: edges, origin: origin)
        return (moved, shift)
    }
}
