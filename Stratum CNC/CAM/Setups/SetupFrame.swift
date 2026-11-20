//
//  SetupFrame.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.11.2026.
//

import Foundation
import simd
import CoreGraphics
import StratumCAM

/// The map from the part's frame (where the model and the canvas shapes live: z0 is the stock
/// top, Y runs from front to back) to a setup's machine frame (z0 is the stock surface that
/// faces up in that setup).
///
/// It is a rotation by −angle about the X (or Y) axis through the stock's centre, followed by a drop
/// of z0 to the surface and, for the side faces, a slide that puts the stock's corner back at the
/// origin (`originShift`). Mapping the geometry before the engine runs, instead of editing G-code
/// afterwards, means climb and conventional cutting come out right by themselves.
///
///     y' = (y − yc)·cos θ + (z − zc)·sin θ + yc + shift
///     z' = −(y − yc)·sin θ + (z − zc)·cos θ − r
///
/// `(yc, zc)` is the axis, `r` the distance from the axis to the surface that faces up. About the Y
/// axis the same holds with x and `xc` in place of y and `yc`.
struct SetupFrame: Sendable, Equatable {

    let angle: Double
    /// The horizontal axis the stock turns about.
    let axis: SetupAxis
    /// Where that axis sits across the stock: its centre in Y for a turn about X, in X for a turn about Y.
    let pivot: Double
    let axisZ: Double
    /// Distance from the axis to the surface that ends up facing up.
    let surfaceDistance: Double

    static let identity = SetupFrame(angle: 0, axis: .x, pivot: 0, axisZ: 0, surfaceDistance: 0)

    var isIdentity: Bool { quarterTurns == 0 }

    /// 0…3 for the four faces; nil for any other angle.
    private var quarterTurns: Int? {
        let quarter = angle / 90
        let rounded = quarter.rounded()
        return abs(quarter - rounded) < 1e-9 ? Int(rounded) % 4 : nil
    }

    // MARK: Building

    /// The frame for a setup on this stock. Throws a message fit for the Generate button when
    /// the angle or the stock can't be handled yet.
    static func make(setup: Setup, stock: StockMaterial?) throws -> SetupFrame {
        try make(angle: setup.angle, axis: setup.axis, stock: stock)
    }

    static func make(angle: Double, axis: SetupAxis = .x, stock: StockMaterial?) throws -> SetupFrame {
        let normalized = Setup.normalized(angle)
        guard normalized != 0 else {
            return .identity
        }
        guard let stock else {
            throw ToolpathGenerator.GenerationError.invalidOption("This setup needs a stock to turn. Choose a material first.")
        }
        let quarter = normalized / 90
        guard abs(quarter - quarter.rounded()) < 1e-9 else {
            throw ToolpathGenerator.GenerationError.invalidOption("Setups between the four faces need a rotary axis, which isn't supported yet.")
        }
        let turns = quarter.roundedInt % 4
        let extents = stock.setupExtents
        // A cylinder or disk is held flat: it can be flipped over, not stood on its side.
        if turns % 2 == 1, !extents.isBox {
            throw ToolpathGenerator.GenerationError.invalidOption("The front, back, left and right setups need a rectangular stock.")
        }
        let across = axis == .x ? extents.y : extents.x
        let up = turns % 2 == 0 ? extents.z : across

        return SetupFrame(angle: normalized,
                          axis: axis,
                          pivot: axis == .x ? extents.centerY : extents.centerX,
                          axisZ: -extents.z / 2,
                          surfaceDistance: up / 2)
    }

    // MARK: Mapping

    /// The slide, along the axis the stock is turned across (Y for a turn about X, X for a turn
    /// about Y), that puts the stock's corner at 0 again. A quarter turn stands the stock on its
    /// edge: it then spans the stock's thickness there instead of its width, still centred on the
    /// pivot, so the front-left corner would no longer be at the origin. The top and the bottom
    /// keep the footprint they had, so they need no slide.
    private var originShift: Double {
        guard let turns = quarterTurns, turns % 2 == 1 else {
            return 0
        }
        // Half the thickness (the axis is at mid-thickness, `axisZ` below z0) from the pivot
        return -axisZ - pivot
    }

    /// Exact for the four faces (no 6e-17 noise from `cos(π/2)`).
    private var cosSin: (c: Double, s: Double) {
        switch quarterTurns {
            case 0?: return (1, 0)
            case 1?: return (0, 1)
            case 2?: return (-1, 0)
            case 3?: return (0, -1)
            default:
                let radians = angle.inRadians
                return (cos(radians), sin(radians))
        }
    }

    /// `map` as a matrix, for drawing: the canvas turns the stock, the model and the shapes
    /// with it so the setup's face is the one facing up, while the origin stays where it was.
    var matrix: simd_float4x4 {
        if isIdentity {
            return matrix_identity_float4x4
        }
        let (c, s) = cosSin
        let t = pivot - c * pivot - s * axisZ + originShift
        let tz = s * pivot - c * axisZ - surfaceDistance
        switch axis {
            case .x:
                return simd_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                               SIMD4<Float>(0, Float(c), Float(-s), 0),
                                               SIMD4<Float>(0, Float(s), Float(c), 0),
                                               SIMD4<Float>(0, Float(t), Float(tz), 1)))
            case .y:
                return simd_float4x4(columns: (SIMD4<Float>(Float(c), 0, Float(-s), 0),
                                               SIMD4<Float>(0, 1, 0, 0),
                                               SIMD4<Float>(Float(s), 0, Float(c), 0),
                                               SIMD4<Float>(Float(t), 0, Float(tz), 1)))
        }
    }

    /// The toolpath overlay's turn: the part's XY mapped to the setup's (a mirror about the
    /// stock's centre line for the bottom: in Y when flipped about X, in X when flipped about Y),
    /// Z untouched. The overlay is flat at z0, and in the setup's frame z0 is the face that is up,
    /// so it must not be dropped with the part.
    /// Identity for every setup but the bottom (the side faces have no top-down overlay).
    var previewMatrix: simd_float4x4 {
        guard quarterTurns == 2 else {
            return matrix_identity_float4x4
        }
        switch axis {
            case .x:
                return simd_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                               SIMD4<Float>(0, -1, 0, 0),
                                               SIMD4<Float>(0, 0, 1, 0),
                                               SIMD4<Float>(0, Float(2 * pivot), 0, 1)))
            case .y:
                return simd_float4x4(columns: (SIMD4<Float>(-1, 0, 0, 0),
                                               SIMD4<Float>(0, 1, 0, 0),
                                               SIMD4<Float>(0, 0, 1, 0),
                                               SIMD4<Float>(Float(2 * pivot), 0, 0, 1)))
        }
    }

    /// Where this setup's z0 plane is in the *part's* frame: the part's top face for the top setup,
    /// the stock's thickness below it for the bottom (whose z0 is the part's underside). A toolpath
    /// preview, flat at z0 and mapped back to the part's XY, is placed at this height.
    var z0InPartFrame: Double {
        quarterTurns == 2 ? -2 * surfaceDistance : 0
    }

    /// Z of the stock's bottom face in the setup's frame: the stock's own thickness below z0.
    /// Nil for the top setup, where the stock's depth says it.
    var bottomZ: Float? {
        isIdentity ? nil : -Float(2 * surfaceDistance)
    }

    func map(_ p: SIMD3<Double>) -> SIMD3<Double> {
        if isIdentity {
            return p
        }
        let (c, s) = cosSin
        let za = p.z - axisZ
        switch axis {
            case .x:
                let ya = p.y - pivot
                return SIMD3(p.x,
                             ya * c + za * s + pivot + originShift,
                             -ya * s + za * c - surfaceDistance)
            case .y:
                let xa = p.x - pivot
                return SIMD3(xa * c + za * s + pivot + originShift,
                             p.y,
                             -xa * s + za * c - surfaceDistance)
        }
    }

    /// The inverse of `map`: a point of the setup's frame back in the part's frame.
    func unmap(_ p: SIMD3<Double>) -> SIMD3<Double> {
        if isIdentity {
            return p
        }
        let (c, s) = cosSin
        let za = p.z + surfaceDistance      // measured along the setup's up axis from the turning axis
        switch axis {
            case .x:
                let u = p.y - pivot - originShift
                return SIMD3(p.x,
                             (u * c - za * s) + pivot,
                             (u * s + za * c) + axisZ)
            case .y:
                let u = p.x - pivot - originShift
                return SIMD3((u * c - za * s) + pivot,
                             p.y,
                             (u * s + za * c) + axisZ)
        }
    }

    /// How far a point of the part (in the part's frame) is from this setup's face, along the
    /// direction that is up in the setup: the setup's own Z, so 0 on the face and negative below it.
    func depth(of point: SIMD3<Float>) -> Float {
        Float(map(SIMD3<Double>(point)).z)
    }

    /// Where a point of the part lands when it is flattened onto this setup's face, in the part's frame:
    /// straight along the setup's up direction, not along the part's own Z. For the top that is
    /// z = 0, for the bottom the stock's underside, for the front, back, left and right the side of the
    /// stock that now faces up (the point slides along Y or X, not along Z).
    func projectOntoFace(_ point: SIMD3<Float>) -> SIMD3<Float> {
        if isIdentity {
            return SIMD3<Float>(point.x, point.y, 0)
        }
        var inSetup = map(SIMD3<Double>(point))
        inSetup.z = 0
        return SIMD3<Float>(unmap(inSetup))
    }

    /// A toolpath preview (built in the machine frame) in the part's frame, which is what the
    /// 2D canvas draws. Only the top and the bottom have a top-down view of the part: the bottom
    /// is the same mirror (its own inverse). Nil for the side faces, which have none.
    func previewInPartFrame(_ path: CGPath?) -> CGPath? {
        guard let path else {
            return nil
        }
        switch quarterTurns {
            case 0?:
                return path
            case 2?:
                var mirror = axis == .x
                    ? CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 2 * pivot)
                    : CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * pivot, ty: 0)
                return path.copy(using: &mirror)
            default:
                return nil
        }
    }

    /// Cutting lines built in this setup's frame (with real Z), in the part's frame relative to the
    /// setup's z0: the same XY mirror as `previewInPartFrame`, and for the bottom Z flipped too (deeper
    /// in the setup is higher in the part). The 3D view adds `z0InPartFrame`.
    /// The front, back, left and right have no top-down view (`previewInPartFrame` is nil) but their
    /// cuts do have a place in the part: each point goes back through `unmap`. Their `z0InPartFrame`
    /// is 0, so those lines are already in the part's frame. Nil only for an angle between faces.
    func previewLines(_ points: [SIMD3<Float>]) -> [SIMD3<Float>]? {
        switch quarterTurns {
            case 0?:
                return points
            case 2?:
                let twicePivot = Float(2 * pivot)
                switch axis {
                    case .x:
                        return points.map { SIMD3<Float>($0.x, twicePivot - $0.y, -$0.z) }
                    case .y:
                        return points.map { SIMD3<Float>(twicePivot - $0.x, $0.y, -$0.z) }
                }
            case 1?, 3?:
                return points.map { SIMD3<Float>(unmap(SIMD3<Double>($0))) }
            default:
                return nil
        }
    }

    /// A 2D canvas shape laid on this setup's face (the one that is up), as the engine needs it.
    /// Shapes are flat, so only X and Y matter; depth comes from the toolpath's Start Z / End Z,
    /// measured from this face.
    ///  - top and sides: the shape stays where it is drawn. The side faces are laid out like the
    ///    setup's own top-down view, with their corner at the origin, so the shape sits on the
    ///    face where it appears there.
    ///  - bottom: mirrored about the stock's centre line, the same mirror the toolpath preview uses
    ///    (`previewInPartFrame`), so the cut lands where the shape is seen through the part.
    func placeFlat(_ contour: SC.Contour) -> SC.Contour {
        guard quarterTurns == 2 else {
            return contour
        }
        return contour.mirrored(about: axis, at: pivot)
    }

    /// Facing sides named as the canvas shows them, in this setup's own coordinates: the bottom
    /// is mirrored by `placeFlat(_: SC.Contour)` (in Y for a flip about X, in X for a flip about
    /// Y), so those two sides trade places. Every other setup keeps the shape where it is drawn.
    func placeFlat(_ sides: FacingSides) -> FacingSides {
        guard quarterTurns == 2 else {
            return sides
        }
        var placed = sides
        switch axis {
            case .x: (placed.front, placed.back) = (sides.back, sides.front)
            case .y: (placed.left, placed.right) = (sides.right, sides.left)
        }
        return placed
    }

    /// The rectangle a facing toolpath covers when it faces the whole stock: the stock's footprint
    /// for the top and the bottom, the face that is up for the front, back, left and right.
    /// Same rectangle as `StockMaterial.footprintContour` for the first two.
    func wholeFaceContour(of stock: StockMaterial) -> SC.Contour {
        guard hasTopDownPreview == false else {
            return stock.footprintContour
        }
        // The face that is up spans the stock's thickness across the axis, from the origin
        let extents = stock.setupExtents
        switch axis {
            case .x:
                return StockMaterial.rectangleContour(minX: 0,
                                                      minY: 0,
                                                      maxX: extents.x,
                                                      maxY: extents.z)
            case .y:
                return StockMaterial.rectangleContour(minX: 0,
                                                      minY: 0,
                                                      maxX: extents.z,
                                                      maxY: extents.y)
        }
    }

    /// Whether the 2D canvas can show this setup's toolpaths and scrub them.
    var hasTopDownPreview: Bool {
        quarterTurns == 0 || quarterTurns == 2
    }
}
