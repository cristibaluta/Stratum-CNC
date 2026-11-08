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

/// How an imported model was turned and moved to sit on the canvas: applied to anything that is
/// still in the file's frame, i.e. the surface meshes.
struct STEPPlacement: Sendable {
    var rotation: simd_float3x3
    var shift: SIMD3<Float>
    /// Nothing to apply, so the original data can be used as it is.
    let isIdentity: Bool

    static let identity = STEPPlacement(rotation: matrix_identity_float3x3, shift: .zero, isIdentity: true)

    init(rotation: simd_float3x3, shift: SIMD3<Float>, isIdentity: Bool = false) {
        self.rotation = rotation
        self.shift = shift
        self.isIdentity = isIdentity
    }

    func point(_ p: SIMD3<Float>) -> SIMD3<Float> { rotation * p + shift }

    /// Directions (normals) only turn.
    func direction(_ d: SIMD3<Float>) -> SIMD3<Float> { rotation * d }
}

extension STEPDisplayGeometry {

    init(origin: SIMD3<Double>, bodies: [Body]) {
        self.origin = origin
        self.bodies = bodies
    }

    /// The same edges turned by `rotation` and moved back to the origin: min X and min Y at 0,
    /// max Z at 0. Edge ids and point order are unchanged.
    func placed(rotation: simd_float3x3) -> (geometry: STEPDisplayGeometry, placement: STEPPlacement) {
        var low = SIMD3<Float>(repeating: .infinity)
        var high = SIMD3<Float>(repeating: -.infinity)
        let turned: [Body] = bodies.map { body in
            let points = body.points.map { rotation * $0 }
            for point in points {
                low = simd_min(low, point)
                high = simd_max(high, point)
            }
            return Body(id: body.id, points: points, edges: body.edges)
        }
        guard low.x.isFinite, low.y.isFinite, high.z.isFinite else { return (self, .identity) }

        let shift = SIMD3<Float>(-low.x, -low.y, -high.z)
        let placed = turned.map { body in
            Body(id: body.id, points: body.points.map { $0 + shift }, edges: body.edges)
        }
        return (STEPDisplayGeometry(origin: origin, bodies: placed),
                STEPPlacement(rotation: rotation, shift: shift))
    }
}
