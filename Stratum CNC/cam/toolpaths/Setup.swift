//
//  Setup.swift
//  Stratum CNC
//
//  A setup is one way the stock is held on the machine. Its orientation is an angle: the
//  rotation of the stock about the machine's X axis, in degrees. Today the angle is one of
//  four faces (top, front, bottom, back); a rotary axis later means any angle, without
//  changing anything stored.
//
//      angle   face     up direction in the part's frame
//      0       top      +Z
//      90      front    −Y   (the face toward the operator; machine Y+ is the back)
//      180     bottom   −Z
//      270     back     +Y
//
//  Toolpaths are generated in the setup's own frame (`SetupFrame`): the part is rotated by
//  −angle about the axis through the stock's centre, and z0 is the stock's surface that is now
//  facing up. Every Z field of a toolpath therefore keeps meaning "depth below this setup's z0".
//

import Foundation
import CoreGraphics
import simd

// MARK: - Face

/// The orientations the app offers today. A setup stores an angle, not a face, so a rotary
/// axis can add other angles without a migration.
enum SetupFace: Int, CaseIterable, Identifiable, Sendable {
    case top = 0
    case front = 90
    case bottom = 180
    case back = 270

    var id: Int { rawValue }

    var angle: Double { Double(rawValue) }

    var title: String {
        switch self {
            case .top:    return "Top"
            case .front:  return "Front"
            case .bottom: return "Bottom"
            case .back:   return "Back"
        }
    }

    /// The face a stored angle is (to the nearest degree), or nil for an angle between faces.
    init?(angle: Double) {
        let normalized = Setup.normalized(angle)
        guard let face = SetupFace.allCases.first(where: { abs($0.angle - normalized) < 0.5 }) else {
            return nil
        }
        self = face
    }
}

// MARK: - Setup

struct Setup: Identifiable, Codable, Hashable, Sendable {

    var id = UUID()
    var name: String
    /// Rotation of the stock about the machine's X axis, degrees, in 0..<360.
    var angle: Double

    init(id: UUID = UUID(), name: String, angle: Double) {
        self.id = id
        self.name = name
        self.angle = Self.normalized(angle)
    }

    init(face: SetupFace, name: String? = nil) {
        self.init(name: name ?? face.title, angle: face.angle)
    }

    /// The face this setup looks at, nil for an angle between faces (a rotary index).
    var face: SetupFace? { SetupFace(angle: angle) }

    /// "Top", "Front"… or "45°" for an angle that is not a face.
    var orientationTitle: String {
        face?.title ?? "\(angle.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    static func normalized(_ angle: Double) -> Double {
        let wrapped = angle.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// A name for a new setup that isn't taken yet: "Front", then "Front 2", "Front 3"…
    static func uniqueName(for face: SetupFace, among taken: Set<String>) -> String {
        guard taken.contains(face.title) else { return face.title }
        var n = 2
        while taken.contains("\(face.title) \(n)") { n += 1 }
        return "\(face.title) \(n)"
    }
}

// MARK: - Frame

/// The map from the part's frame (where the model and the canvas shapes live: z0 is the stock
/// top, Y runs from front to back) to a setup's machine frame (z0 is the stock surface that
/// faces up in that setup).
///
/// It is a rotation by −angle about the X axis through the stock's centre, followed by a drop
/// of z0 to the surface. Mapping the geometry before the engine runs, instead of editing G-code
/// afterwards, means climb and conventional cutting come out right by themselves.
///
///     y' = (y − yc)·cos θ + (z − zc)·sin θ + yc
///     z' = −(y − yc)·sin θ + (z − zc)·cos θ − r
///
/// `(yc, zc)` is the axis, `r` the distance from the axis to the surface that faces up.
struct SetupFrame: Sendable, Equatable {

    let angle: Double
    let axisY: Double
    let axisZ: Double
    /// Distance from the axis to the surface that ends up facing up.
    let surfaceDistance: Double

    static let identity = SetupFrame(angle: 0, axisY: 0, axisZ: 0, surfaceDistance: 0)

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
    static func make(angle: Double, stock: StockMaterial?) throws -> SetupFrame {
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
                "The front and back setups need a rectangular stock.")
        }
        let up = turns % 2 == 0 ? extents.z : extents.y
        return SetupFrame(angle: normalized,
                          axisY: extents.centerY,
                          axisZ: -extents.z / 2,
                          surfaceDistance: up / 2)
    }

    // MARK: Mapping

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
        let ty = axisY - c * axisY - s * axisZ
        let tz = s * axisY - c * axisZ - surfaceDistance
        return simd_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                       SIMD4<Float>(0, Float(c), Float(-s), 0),
                                       SIMD4<Float>(0, Float(s), Float(c), 0),
                                       SIMD4<Float>(0, Float(ty), Float(tz), 1)))
    }

    /// The toolpath overlay's turn: the part's XY mapped to the setup's (a mirror in Y about the
    /// stock's centre line for the bottom), Z untouched. The overlay is flat at z0, and in the
    /// setup's frame z0 is the face that is up, so it must not be dropped with the part.
    /// Identity for every setup but the bottom (front and back have no top-down overlay).
    var previewMatrix: simd_float4x4 {
        guard quarterTurns == 2 else { return matrix_identity_float4x4 }
        return simd_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                       SIMD4<Float>(0, -1, 0, 0),
                                       SIMD4<Float>(0, 0, 1, 0),
                                       SIMD4<Float>(0, Float(2 * axisY), 0, 1)))
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
        let ya = p.y - axisY
        let za = p.z - axisZ
        return SIMD3(p.x,
                     ya * c + za * s + axisY,
                     -ya * s + za * c - surfaceDistance)
    }

    /// A toolpath preview (built in the machine frame) in the part's frame, which is what the
    /// 2D canvas draws. Only the top and the bottom have a top-down view of the part: the bottom
    /// is the same mirror in Y (its own inverse). Nil for front and back, which have none.
    func previewInPartFrame(_ path: CGPath?) -> CGPath? {
        guard let path else { return nil }
        switch quarterTurns {
            case 0?:
                return path
            case 2?:
                var mirror = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 2 * axisY)
                return path.copy(using: &mirror)
            default:
                return nil
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
    /// Size along Y (front to back) and Z (thickness), mm.
    let y: Double
    let z: Double
    /// Where the stock's centre line sits in Y on the canvas.
    let centerY: Double
    /// A rectangular block, which can be stood on any of its four long sides.
    let isBox: Bool
}

extension StockMaterial {

    /// ASSUMPTION to check: the stock sits with its front edge at Y = 0 and its top at Z = 0
    /// (the same z0 the toolpaths are cut from), so its centre line is at `y / 2`. If the canvas
    /// centres the stock on the origin instead, return 0 for `centerY`: it is the only place
    /// that knows.
    var setupExtents: SetupStockExtents {
        switch geometry {
            case .rectangular(_, let width, let height):
                return SetupStockExtents(y: width, z: height, centerY: width / 2, isBox: true)
            case .cylindrical(let diameter, let length):
                return SetupStockExtents(y: diameter, z: length, centerY: diameter / 2, isBox: false)
            case .disk(let outerDiameter, _, let height):
                return SetupStockExtents(y: outerDiameter, z: height, centerY: outerDiameter / 2, isBox: false)
        }
    }
}
