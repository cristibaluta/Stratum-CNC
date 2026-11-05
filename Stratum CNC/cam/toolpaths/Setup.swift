//
//  Setup.swift
//  Stratum CNC
//
//  A setup is one way the stock is held on the machine. Its orientation is a rotation of the
//  stock by an angle, in degrees, about a horizontal machine axis through the stock's centre
//  (X or Y). Today the angle is one of four quarter turns; a rotary axis later means any angle,
//  without changing anything stored.
//
//      face     axis  angle   up direction in the part's frame
//      top      -     0       +Z
//      front    X     90      −Y   (the face toward the operator; machine Y+ is the back)
//      bottom   X|Y   180     −Z   (flipped over about X: shapes mirror in Y; about Y: in X)
//      back     X     270     +Y
//      left     Y     90      −X
//      right    Y     270     +X
//
//  Toolpaths are generated in the setup's own frame (`SetupFrame`): the part is rotated by
//  −angle about the axis through the stock's centre, and z0 is the stock's surface that is now
//  facing up. Every Z field of a toolpath therefore keeps meaning "depth below this setup's z0".
//  A side face stands the stock on its edge, so its footprint is another size: it is slid back
//  to the origin, with its corner at X = 0, Y = 0, like the top's.
//

import Foundation
import CoreGraphics
import simd
import StratumCAM

// MARK: - Face

/// The horizontal machine axis a setup turns the stock about.
enum SetupAxis: String, Codable, CaseIterable, Identifiable, Sendable {
    case x
    case y

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }
}

/// The orientations the app offers today. A setup stores an angle and an axis, not a face, so a
/// rotary axis can add other angles without a migration.
enum SetupFace: CaseIterable, Identifiable, Sendable {
    case top
    case front
    case bottom
    case back
    case left
    case right

    var id: Self { self }

    var angle: Double {
        switch self {
            case .top:            return 0
            case .front, .left:   return 90
            case .bottom:         return 180
            case .back, .right:   return 270
        }
    }

    /// The axis that reaches this face. The bottom can be reached about either: this is its default.
    var axis: SetupAxis {
        switch self {
            case .left, .right: return .y
            default:            return .x
        }
    }

    /// The faces that can be reached about more than one axis: which one decides what mirrors.
    var hasChoiceOfAxis: Bool { self == .bottom }

    /// The side faces stand the stock on its edge: they need a 3D model to make sense of.
    var isSide: Bool {
        switch self {
            case .front, .back, .left, .right: return true
            default:                           return false
        }
    }

    var title: String {
        switch self {
            case .top:    return "Top"
            case .front:  return "Front"
            case .bottom: return "Bottom"
            case .back:   return "Back"
            case .left:   return "Left"
            case .right:  return "Right"
        }
    }

    /// The face a stored rotation is (to the nearest degree), or nil for an angle between faces.
    init?(angle: Double, axis: SetupAxis = .x) {
        let normalized = Setup.normalized(angle)
        guard let face = SetupFace.allCases.first(where: {
            abs($0.angle - normalized) < 0.5 && ($0.axis == axis || $0.hasChoiceOfAxis || $0 == .top)
        }) else {
            return nil
        }
        self = face
    }
}

// MARK: - Setup

/// A rotation of the stock, to tell whether a setup's results are still valid.
struct SetupOrientation: Hashable, Sendable {
    var angle: Double
    var axis: SetupAxis
}

struct Setup: Identifiable, Codable, Hashable, Sendable {

    var id = UUID()
    var name: String
    /// Rotation of the stock about `axis`, degrees, in 0..<360.
    var angle: Double
    /// The machine axis the stock turns about.
    var axis: SetupAxis

    init(id: UUID = UUID(), name: String, angle: Double, axis: SetupAxis = .x) {
        self.id = id
        self.name = name
        self.angle = Self.normalized(angle)
        self.axis = axis
    }

    init(face: SetupFace, axis: SetupAxis? = nil, name: String? = nil) {
        let axis = face.hasChoiceOfAxis ? (axis ?? face.axis) : face.axis
        self.init(name: name ?? Self.baseName(for: face, axis: axis), angle: face.angle, axis: axis)
    }

    var orientation: SetupOrientation { SetupOrientation(angle: angle, axis: axis) }

    /// The face this setup looks at, nil for an angle between faces (a rotary index).
    var face: SetupFace? { SetupFace(angle: angle, axis: axis) }

    /// "Top", "Front"… ("Bottom (flip Y)" when flipped about Y) or "45°" for an angle that is not a face.
    var orientationTitle: String {
        face.map { Self.baseName(for: $0, axis: axis) }
            ?? "\(angle.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    /// The default name of a face: its title, with the flip axis when that is not the usual X.
    static func baseName(for face: SetupFace, axis: SetupAxis) -> String {
        face.hasChoiceOfAxis && axis != face.axis ? "\(face.title) (flip \(axis.title))" : face.title
    }

    static func normalized(_ angle: Double) -> Double {
        let wrapped = angle.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// A name for a new setup that isn't taken yet: "Front", then "Front 2", "Front 3"…
    static func uniqueName(for face: SetupFace, axis: SetupAxis? = nil, among taken: Set<String>) -> String {
        let base = baseName(for: face, axis: axis ?? face.axis)
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

// MARK: - Frame

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
            throw ToolpathGenerator.GenerationError.invalidOption(
                "Setups between the four faces need a rotary axis, which isn't supported yet.")
        }
        let turns = Int(quarter.rounded()) % 4
        let extents = stock.setupExtents
        // A cylinder or disk is held flat: it can be flipped over, not stood on its side.
        if turns % 2 == 1, !extents.isBox {
            throw ToolpathGenerator.GenerationError.invalidOption(
                "The front, back, left and right setups need a rectangular stock.")
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
        guard let turns = quarterTurns, turns % 2 == 1 else { return 0 }
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
                let radians = angle * .pi / 180
                return (cos(radians), sin(radians))
        }
    }

    /// `map` as a matrix, for drawing: the canvas turns the stock, the model and the shapes
    /// with it so the setup's face is the one facing up, while the origin stays where it was.
    var matrix: simd_float4x4 {
        if isIdentity { return matrix_identity_float4x4 }
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
        guard quarterTurns == 2 else { return matrix_identity_float4x4 }
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
        if isIdentity { return p }
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

    /// A toolpath preview (built in the machine frame) in the part's frame, which is what the
    /// 2D canvas draws. Only the top and the bottom have a top-down view of the part: the bottom
    /// is the same mirror (its own inverse). Nil for the side faces, which have none.
    func previewInPartFrame(_ path: CGPath?) -> CGPath? {
        guard let path else { return nil }
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

    /// A 2D canvas shape laid on this setup's face (the one that is up), as the engine needs it.
    /// Shapes are flat, so only X and Y matter; depth comes from the toolpath's Start Z / End Z,
    /// measured from this face.
    ///  - top and sides: the shape stays where it is drawn. The side faces are laid out like the
    ///    setup's own top-down view, with their corner at the origin, so the shape sits on the
    ///    face where it appears there.
    ///  - bottom: mirrored about the stock's centre line, the same mirror the toolpath preview uses
    ///    (`previewInPartFrame`), so the cut lands where the shape is seen through the part.
    func placeFlat(_ contour: SC.Contour) -> SC.Contour {
        guard quarterTurns == 2 else { return contour }
        return contour.mirrored(about: axis, at: pivot)
    }

    /// The rectangle a facing toolpath covers when it faces the whole stock: the stock's footprint
    /// for the top and the bottom, the face that is up for the front, back, left and right.
    /// Same rectangle as `StockMaterial.footprintContour` for the first two.
    func wholeFaceContour(of stock: StockMaterial) -> SC.Contour {
        guard hasTopDownPreview == false else { return stock.footprintContour }
        // The face that is up spans the stock's thickness across the axis, from the origin
        let extents = stock.setupExtents
        switch axis {
            case .x:
                return StockMaterial.rectangleContour(minX: 0, minY: 0,
                                                      maxX: extents.x, maxY: extents.z)
            case .y:
                return StockMaterial.rectangleContour(minX: 0, minY: 0,
                                                      maxX: extents.z, maxY: extents.y)
        }
    }

    /// Whether the 2D canvas can show this setup's toolpaths and scrub them.
    var hasTopDownPreview: Bool {
        quarterTurns == 0 || quarterTurns == 2
    }
}

// MARK: - Stock extents

/// What `SetupFrame` needs to know about the stock, in the part's frame.
struct SetupStockExtents {
    /// Size along X (left to right), Y (front to back) and Z (thickness), mm.
    let x: Double
    let y: Double
    let z: Double
    /// Where the stock's centre lines sit in X and Y on the canvas.
    let centerX: Double
    let centerY: Double
    /// A rectangular block, which can be stood on any of its four long sides.
    let isBox: Bool
}

extension StockMaterial {

    /// ASSUMPTION to check: the stock sits with its front-left corner at X = 0, Y = 0 and its top at
    /// Z = 0 (the same z0 the toolpaths are cut from), so its centre lines are at `x / 2` and `y / 2`. If the canvas
    /// centres the stock on the origin instead, return 0 for `centerX` and `centerY`: it is the only
    /// place that knows.
    var setupExtents: SetupStockExtents {
        switch geometry {
            case .rectangular(let length, let width, let height):
                return SetupStockExtents(x: length, y: width, z: height,
                                         centerX: length / 2, centerY: width / 2, isBox: true)
            case .cylindrical(let diameter, let length):
                return SetupStockExtents(x: diameter, y: diameter, z: length,
                                         centerX: diameter / 2, centerY: diameter / 2, isBox: false)
            case .disk(let outerDiameter, _, let height):
                return SetupStockExtents(x: outerDiameter, y: outerDiameter, z: height,
                                         centerX: outerDiameter / 2, centerY: outerDiameter / 2, isBox: false)
        }
    }
}
