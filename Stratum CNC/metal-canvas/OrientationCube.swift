//
//  OrientationCube.swift
//  Stratum CNC
//
//  The little orientation cube drawn in a corner of the canvas. It's a
//  fixed-size, always-on-top indicator of how the world is currently turned
//  relative to the screen — see `MetalRenderer.drawOrientationCube`.
//
//  Like `RenderObject`, this file is plain data: it only builds vertices.
//  Buffers, viewports and draw calls all live in `MetalRenderer`.
//
//  The cube follows the machine's axes: +X red, +Y green, +Z blue (the same
//  colors as `RenderObject.axes`). Each face carries the letter of the axis
//  it points along — a plain letter on a light face for the positive side,
//  "-" + letter on a darker face for the negative side. +Z is the top face
//  and -Z the bottom, so at the default view it reads as a "Z" square.
//
//  Everything is solid triangles (Metal has no line width, and a 1px
//  outline would vanish at this size), using the same vertex layout and
//  pipeline as the rest of the scene.
//

import Foundation
import CoreGraphics
import simd

enum OrientationCube {

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Which corner of the canvas the cube sits in.
    static let corner: Corner = .bottomRight
    /// Side of the square the cube is drawn in, and its gap to the canvas
    /// edges, both in view points (scaled to pixels at draw time).
    static let size: CGFloat = 96
    static let margin: CGFloat = 12
    /// Half-size of the projected square, in cube units (cube half-size is
    /// 1, so its corner radius is √3 ≈ 1.73). See `Camera.orientationCubeMatrix`.
    static let halfExtent: Float = 1.9

    // MARK: - Geometry

    /// Every triangle of the cube (three faces of it are visible at once;
    /// the depth test sorts out which). Static: the cube is never rebuilt,
    /// the camera's rotation is applied through the MVP instead.
    static func makeCubeVertices() -> [RenderVertex] {
        var vertices: [RenderVertex] = []
        for face in faces {
            append(face, into: &vertices)
        }
        return vertices
    }

    /// Two triangles covering the whole clip-space square at (almost) the
    /// far plane. Drawn with depth compare `.always` and color writes off,
    /// this resets the depth buffer inside the cube's viewport so the cube
    /// isn't hidden by — or z-fighting with — the scene behind it.
    static func makeDepthResetVertices() -> [RenderVertex] {
        let z: Float = 0.999
        let corners = [SIMD3<Float>(-1, -1, z), SIMD3<Float>(1, -1, z),
                       SIMD3<Float>(1, 1, z), SIMD3<Float>(-1, 1, z)]
        return [0, 1, 2, 0, 2, 3].map {
            RenderVertex(position: corners[$0], color: SIMD4<Float>(repeating: 0), dist: 0)
        }
    }

    // MARK: - Faces

    private enum Letter {
        case x, y, z

        /// Strokes as (x0, y0, x1, y1) in face units, centered on the origin.
        var strokes: [SIMD4<Float>] {
            let w: Float = 0.36
            let h: Float = 0.52
            switch self {
            case .x:
                return [SIMD4<Float>(-w, -h, w, h),
                        SIMD4<Float>(-w, h, w, -h)]
            case .y:
                return [SIMD4<Float>(-w, h, 0, 0.05),
                        SIMD4<Float>(w, h, 0, 0.05),
                        SIMD4<Float>(0, 0.05, 0, -h)]
            case .z:
                return [SIMD4<Float>(-w, h, w, h),
                        SIMD4<Float>(w, h, -w, -h),
                        SIMD4<Float>(-w, -h, w, -h)]
            }
        }
    }

    /// One face of the cube (half-size 1, centered on the origin). `up` is
    /// the world direction that points up the label; its right-hand
    /// direction is derived from it, so the letter reads correctly — never
    /// mirrored — when the face is viewed from outside the cube. These are
    /// the same "up" choices as `StandardView`.
    private struct Face {
        let normal: SIMD3<Float>
        let up: SIMD3<Float>
        let letter: Letter
        let isPositive: Bool
        let axisColor: SIMD3<Float>

        var right: SIMD3<Float> { simd_cross(up, normal) }

        /// A point on the face at (a, b) in face units, `lift` above the
        /// surface — the small lift layers the fill and the letter over the
        /// face without z-fighting.
        func point(_ a: Float, _ b: Float, lift: Float) -> SIMD3<Float> {
            normal * (1 + lift) + right * a + up * b
        }
    }

    // Same colors as `RenderObject.axes`.
    private static let red = SIMD3<Float>(1.0, 0.15, 0.15)
    private static let green = SIMD3<Float>(0.15, 1.0, 0.15)
    private static let blue = SIMD3<Float>(0.15, 0.45, 1.0)

    private static let faces: [Face] = [
        Face(normal: SIMD3<Float>(1, 0, 0), up: SIMD3<Float>(0, 0, 1), letter: .x, isPositive: true, axisColor: red),
        Face(normal: SIMD3<Float>(-1, 0, 0), up: SIMD3<Float>(0, 0, 1), letter: .x, isPositive: false, axisColor: red),
        Face(normal: SIMD3<Float>(0, 1, 0), up: SIMD3<Float>(0, 0, 1), letter: .y, isPositive: true, axisColor: green),
        Face(normal: SIMD3<Float>(0, -1, 0), up: SIMD3<Float>(0, 0, 1), letter: .y, isPositive: false, axisColor: green),
        Face(normal: SIMD3<Float>(0, 0, 1), up: SIMD3<Float>(0, 1, 0), letter: .z, isPositive: true, axisColor: blue),
        Face(normal: SIMD3<Float>(0, 0, -1), up: SIMD3<Float>(0, -1, 0), letter: .z, isPositive: false, axisColor: blue),
    ]

    // MARK: - Building

    private static func append(_ face: Face, into vertices: inout [RenderVertex]) {
        let outline = SIMD4<Float>(0.06, 0.06, 0.06, 1)

        let fill: SIMD3<Float>
        let ink: SIMD3<Float>
        if face.isPositive {
            // Bright pastel of the axis color, dark letter.
            fill = lerp(face.axisColor, SIMD3<Float>(repeating: 1), 0.45)
            ink = SIMD3<Float>(repeating: 0.08)
        } else {
            // Muted dark version of it, light letter — so the two ends of
            // an axis are easy to tell apart.
            fill = lerp(face.axisColor, SIMD3<Float>(repeating: 0.25), 0.55)
            ink = SIMD3<Float>(repeating: 0.96)
        }

        // Dark outline = the full face; the fill sits slightly inside and
        // above it, leaving a thin border where two faces meet.
        appendQuad(face.point(-1, -1, lift: 0), face.point(1, -1, lift: 0),
                   face.point(1, 1, lift: 0), face.point(-1, 1, lift: 0),
                   color: outline, into: &vertices)
        appendQuad(face.point(-0.88, -0.88, lift: 0.01), face.point(0.88, -0.88, lift: 0.01),
                   face.point(0.88, 0.88, lift: 0.01), face.point(-0.88, 0.88, lift: 0.01),
                   color: SIMD4<Float>(fill, 1), into: &vertices)

        // Label. Negative faces get a minus sign to the left of the letter,
        // with the letter shifted right to keep the pair centered.
        let inkColor = SIMD4<Float>(ink, 1)
        let shift: Float = face.isPositive ? 0 : 0.32
        for s in face.letter.strokes {
            appendStroke(face, from: SIMD2<Float>(s.x + shift, s.y), to: SIMD2<Float>(s.z + shift, s.w),
                         color: inkColor, into: &vertices)
        }
        if !face.isPositive {
            appendStroke(face, from: SIMD2<Float>(-0.68, 0), to: SIMD2<Float>(-0.34, 0),
                         color: inkColor, into: &vertices)
        }
    }

    /// A stroke as a thin quad in the face plane, with square end caps.
    private static func appendStroke(_ face: Face,
                                     from a: SIMD2<Float>,
                                     to b: SIMD2<Float>,
                                     color: SIMD4<Float>,
                                     into vertices: inout [RenderVertex]) {
        let halfWidth: Float = 0.085
        let lift: Float = 0.02
        let d = simd_normalize(b - a)
        let n = SIMD2<Float>(-d.y, d.x)
        let a2 = a - d * halfWidth
        let b2 = b + d * halfWidth

        func p(_ q: SIMD2<Float>) -> SIMD3<Float> {
            face.point(q.x, q.y, lift: lift)
        }
        appendQuad(p(a2 + n * halfWidth), p(b2 + n * halfWidth),
                   p(b2 - n * halfWidth), p(a2 - n * halfWidth),
                   color: color, into: &vertices)
    }

    private static func appendQuad(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>,
                                   _ p2: SIMD3<Float>, _ p3: SIMD3<Float>,
                                   color: SIMD4<Float>,
                                   into vertices: inout [RenderVertex]) {
        for p in [p0, p1, p2, p0, p2, p3] {
            vertices.append(RenderVertex(position: p, color: color, dist: 0))
        }
    }

    private static func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}
