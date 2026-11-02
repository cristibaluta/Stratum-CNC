import Foundation
import simd

// MARK: - Geometry

/// Right-handed orthonormal frame from an AXIS2_PLACEMENT_3D, in millimetres.
struct STEPFrame {
    let origin: SIMD3<Double>
    let x: SIMD3<Double>
    let y: SIMD3<Double>
    let z: SIMD3<Double>
}

/// Circle in its own frame: P(t) = origin + radius * (cos t * x + sin t * y).
struct STEPCircleGeometry {
    let frame: STEPFrame
    let radius: Double // mm

    func point(at angle: Double) -> SIMD3<Double> {
        frame.origin + radius * (cos(angle) * frame.x + sin(angle) * frame.y)
    }

    /// Parameter of the closest in-plane direction, and how far `point` is from the circle
    /// (out-of-plane offset included).
    func projection(of point: SIMD3<Double>) -> (angle: Double, distance: Double) {
        let offset = point - frame.origin
        let angle = atan2(simd_dot(offset, frame.y), simd_dot(offset, frame.x))
        return (angle, simd_distance(point, self.point(at: angle)))
    }
}

enum STEPAngle {
    static let twoPi = 2 * Double.pi

    /// Folds into [0, 2π).
    static func wrapped(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: twoPi)
        let folded = remainder < 0 ? remainder + twoPi : remainder
        return folded >= twoPi ? 0 : folded
    }

    /// Smallest absolute difference between two angles, in [0, π].
    static func distance(_ a: Double, _ b: Double) -> Double {
        let difference = wrapped(a - b)
        return min(difference, twoPi - difference)
    }
}

// MARK: - Sampling

enum STEPArcSampler {
    /// Also the minimum resolution: a full circle never has fewer than 8 segments,
    /// so tiny circles stay round instead of collapsing to a chord.
    static let maximumAngularStep = Double.pi / 4
    static let maximumSegments = 4096

    struct Plan {
        let segments: Int
        /// Actual sagitta (mm) of the chosen subdivision.
        let chordError: Double
    }

    /// Sagitta of a chord spanning step Δ is 2R·sin²(Δ/4). Solving for Δ this way
    /// stays accurate for huge R/tolerance ratios, where 1 - cos(Δ/2) cancels.
    static func plan(radius: Double, sweep: Double, tolerance: Double) -> Plan {
        let magnitude = abs(sweep)
        let ratio = min(2, tolerance / radius)
        let toleranceStep = 4 * asin(min(1, (ratio / 2).squareRoot()))
        let step = min(toleranceStep, maximumAngularStep)
        // The epsilon keeps float noise (e.g. 2.0000000000000004) from adding a segment.
        let wanted = step > 0 ? (magnitude / step - 1e-9).rounded(.up) : Double.infinity
        let segments = Int(min(max(wanted, 1), Double(maximumSegments)))
        let actualStep = magnitude / Double(segments)
        let sine = sin(actualStep / 4)
        return Plan(segments: segments, chordError: 2 * radius * sine * sine)
    }
}

// MARK: - Trims

struct STEPTrimSpec {
    enum Master { case cartesian, parameter, unspecified }
    struct Bound {
        var point: SIMD3<Double>? // mm
        var parameter: Double?    // raw, in the context's angle unit
    }
    let first: Bound
    let second: Bound
    /// True when the trimmed curve runs in the basis curve's direction.
    let senseAgreement: Bool
    let master: Master
}

struct STEPResolvedCurve {
    let kind: STEPEdge.CurveKind
    let points: [SIMD3<Double>] // mm; first/last are exactly the scaled vertex coordinates
    let chordError: Double
    let warning: String?
}

// MARK: - Resolver

/// Turns an EDGE_CURVE's geometry plus its vertices into display points.
/// Task-confined, like `STEPFile`. All results are in millimetres.
final class STEPCurveResolver {
    private let file: STEPFile
    private let scale: Double
    private let chordTolerance: Double
    private let angleScale: () throws -> Double
    private static let wrappers: Set<String> = ["SURFACE_CURVE", "SEAM_CURVE", "INTERSECTION_CURVE"]
    /// Slack (rad) when comparing trim angles with vertex angles and detecting a full turn.
    private static let angularTolerance = 1e-3

    init(file: STEPFile, scaleToMM: Double, chordTolerance: Double,
         angleScaleToRadians: @escaping () throws -> Double) {
        self.file = file
        scale = scaleToMM
        self.chordTolerance = chordTolerance
        angleScale = angleScaleToRadians
    }

    /// `startVertexID`/`endVertexID` are canonical EDGE_CURVE order; `sameSense` says whether
    /// start → end runs along `curveID`'s own direction. ORIENTED_EDGE never reaches here.
    func resolve(curveID: Int, startVertexID: Int, endVertexID: Int, sameSense: Bool) throws -> STEPResolvedCurve {
        let (basisID, trimParameters) = try peel(curveID)

        if file.hasType(basisID, "LINE") {
            // A line is fully determined by its vertices; trims add nothing for display.
            let points = [try vertex(startVertexID), try vertex(endVertexID)]
            guard points[0] != points[1] else { throw STEPParseError("Degenerate line edge") }
            return STEPResolvedCurve(kind: .line, points: points, chordError: 0, warning: nil)
        }
        guard file.hasType(basisID, "CIRCLE") else {
            let names = try file.components(basisID).map(\.type).joined(separator: "/")
            throw STEPParseError("Unsupported curve \(names) at #\(basisID); edge skipped")
        }

        let circle = try circleGeometry(basisID)
        let trim = try trimParameters.map { try trimSpec($0) }
        let start = try vertex(startVertexID)
        let end = try vertex(endVertexID)
        let span = try arcSpan(circle: circle, trim: trim, start: start, end: end,
                               startVertexID: startVertexID, endVertexID: endVertexID, sameSense: sameSense)

        let plan = STEPArcSampler.plan(radius: circle.radius, sweep: span.sweep, tolerance: chordTolerance)
        var points: [SIMD3<Double>] = []
        points.reserveCapacity(plan.segments + 1)
        for index in 0...plan.segments {
            points.append(circle.point(at: span.start + span.sweep * Double(index) / Double(plan.segments)))
        }
        points[0] = start
        points[plan.segments] = end
        guard points.allSatisfy({ point in (0..<3).allSatisfy { point[$0].isFinite } }) else {
            throw STEPParseError("Nonfinite sampled circle points")
        }
        var warning: String?
        if plan.chordError > chordTolerance * (1 + 1e-9) {
            warning = String(format: "Circular edge approximated with %ld segments; chord error %.3g mm exceeds the %.3g mm tolerance",
                             plan.segments, plan.chordError, chordTolerance)
        }
        return STEPResolvedCurve(kind: span.isFull ? .circle : .arc, points: points,
                                 chordError: plan.chordError, warning: warning)
    }

    // MARK: Wrappers

    /// Follows SURFACE_CURVE-style wrappers to curve_3d and records at most one TRIMMED_CURVE
    /// on the way. Trim parameters stay raw: only curves that use them parse them.
    private func peel(_ id: Int) throws -> (basis: Int, trim: [STEPValue]?) {
        var current = id
        var visited: Set<Int> = []
        var trim: [STEPValue]?
        while true {
            try Task.checkCancellation()
            guard visited.count < 64, visited.insert(current).inserted else {
                throw STEPParseError("Cyclic/deep curve reference #\(current)")
            }
            let parts = try file.components(current)
            if let wrapper = parts.first(where: { Self.wrappers.contains($0.type) }) {
                current = try wrapper.parameters.reference(at: 1)
            } else if let trimmed = parts.first(where: { $0.type == "TRIMMED_CURVE" }) {
                guard trim == nil else {
                    throw STEPParseError("Nested trimmed curves at #\(current) are not supported")
                }
                trim = trimmed.parameters
                current = try trimmed.parameters.reference(at: 1)
            } else {
                return (current, trim)
            }
        }
    }

    // MARK: Placement

    private func cartesianPoint(_ id: Int) throws -> SIMD3<Double> {
        let point = try file.parameters(id, type: "CARTESIAN_POINT")
        guard let coordinates = try point.argument(1).list, coordinates.count == 3 else {
            throw STEPParseError("Expected 3D coordinates at #\(id)")
        }
        var result = SIMD3<Double>.zero
        for axis in 0..<3 {
            guard let value = coordinates[axis].number, value.isFinite, (value * scale).isFinite else {
                throw STEPParseError("Nonfinite/invalid point #\(id)")
            }
            result[axis] = value * scale
        }
        return result
    }

    /// Scaled to millimetres, like every other point.
    func vertex(_ id: Int) throws -> SIMD3<Double> {
        let vertex = try file.parameters(id, type: "VERTEX_POINT")
        let point = try file.parameters(vertex.reference(at: 1), type: "CARTESIAN_POINT")
        guard let coordinates = try point.argument(1).list, coordinates.count == 3 else {
            throw STEPParseError("Expected 3D vertex coordinates at #\(id)")
        }
        var result = SIMD3<Double>.zero
        for axis in 0..<3 {
            guard let value = coordinates[axis].number, value.isFinite, (value * scale).isFinite else {
                throw STEPParseError("Nonfinite/invalid vertex #\(id)")
            }
            result[axis] = value * scale
        }
        return result
    }

    /// Unit vector; direction ratios in the file need not be normalized.
    private func direction(_ id: Int) throws -> SIMD3<Double> {
        let parameters = try file.parameters(id, type: "DIRECTION")
        guard let ratios = try parameters.argument(1).list, ratios.count == 3 else {
            throw STEPParseError("Expected 3D direction at #\(id)")
        }
        var vector = SIMD3<Double>.zero
        for axis in 0..<3 {
            guard let value = ratios[axis].number, value.isFinite else {
                throw STEPParseError("Nonfinite direction #\(id)")
            }
            vector[axis] = value
        }
        let length = simd_length(vector)
        guard length.isFinite, length > 0 else { throw STEPParseError("Zero-length direction #\(id)") }
        return vector / length
    }

    private func optionalDirection(_ value: STEPValue) throws -> SIMD3<Double>? {
        switch value {
            case .unset: return nil
            case .reference(let id): return try direction(id)
            default: throw STEPParseError("Expected direction reference or $")
        }
    }

    /// ISO 10303-42 build_axes: z = axis (default +Z); x = ref_direction made perpendicular to z
    /// (default: world Z, or world X when z is already ±Z); y = z × x.
    private func frame(_ id: Int) throws -> STEPFrame {
        let p = try file.parameters(id, type: "AXIS2_PLACEMENT_3D")
        let origin = try cartesianPoint(p.reference(at: 1))
        let z = try optionalDirection(p.argument(2)) ?? SIMD3<Double>(0, 0, 1)
        let seed = try optionalDirection(p.argument(3))
            ?? (abs(z.z) > 1 - 1e-12 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 0, 1))
        let projected = seed - simd_dot(seed, z) * z
        let length = simd_length(projected)
        // The seed is a unit vector, so this is sin of its angle to the axis.
        guard length > 1e-9 else {
            throw STEPParseError("Degenerate placement #\(id): reference direction is parallel to the axis")
        }
        let x = projected / length
        return STEPFrame(origin: origin, x: x, y: simd_cross(z, x), z: z)
    }

    private func circleGeometry(_ id: Int) throws -> STEPCircleGeometry {
        let p = try file.parameters(id, type: "CIRCLE")
        let frame = try frame(p.reference(at: 1))
        guard let radius = try p.argument(2).number, radius.isFinite, radius > 0,
              (radius * scale).isFinite, radius * scale > 0 else {
            throw STEPParseError("Invalid circle radius at #\(id)")
        }
        return STEPCircleGeometry(frame: frame, radius: radius * scale)
    }

    // MARK: Trims

    private func trimSpec(_ p: [STEPValue]) throws -> STEPTrimSpec {
        guard let sense = try p.argument(4).enumeration, sense == "T" || sense == "F" else {
            throw STEPParseError("Invalid TRIMMED_CURVE sense_agreement")
        }
        let masters: [String: STEPTrimSpec.Master] = ["CARTESIAN": .cartesian, "PARAMETER": .parameter,
                                                      "UNSPECIFIED": .unspecified]
        guard let name = try p.argument(5).enumeration, let master = masters[name] else {
            throw STEPParseError("Invalid TRIMMED_CURVE master_representation")
        }
        return STEPTrimSpec(first: try bound(p.argument(2)), second: try bound(p.argument(3)),
                            senseAgreement: sense == "T", master: master)
    }

    /// A trimming SET holds one point and/or one PARAMETER_VALUE.
    private func bound(_ value: STEPValue) throws -> STEPTrimSpec.Bound {
        guard let items = value.list, (1...2).contains(items.count) else {
            throw STEPParseError("Invalid trimming selection")
        }
        var bound = STEPTrimSpec.Bound()
        for item in items {
            if let id = item.reference {
                guard bound.point == nil else { throw STEPParseError("Duplicate trim point") }
                bound.point = try cartesianPoint(id)
            } else if case .typed("PARAMETER_VALUE", let values) = item, values.count == 1,
                      let number = values[0].number, number.isFinite {
                guard bound.parameter == nil else { throw STEPParseError("Duplicate trim parameter") }
                bound.parameter = number
            } else {
                throw STEPParseError("Unsupported trimming selection")
            }
        }
        return bound
    }

    private func optionalAngleScale() throws -> Double? {
        do { return try angleScale() } catch is STEPParseError { return nil }
    }

    private func angle(of bound: STEPTrimSpec.Bound, master: STEPTrimSpec.Master,
                       circle: STEPCircleGeometry, tolerance: Double) throws -> Double {
        let usePoint: Bool
        switch master {
            case .parameter: usePoint = bound.parameter == nil
            case .cartesian, .unspecified: usePoint = bound.point != nil
        }
        if usePoint {
            guard let point = bound.point else { throw STEPParseError("Trim has neither point nor parameter") }
            let projection = circle.projection(of: point)
            guard projection.distance <= tolerance else { throw STEPParseError("Trim point is not on the circle") }
            return projection.angle
        }
        guard let parameter = bound.parameter else { throw STEPParseError("Trim has neither point nor parameter") }
        return try parameter * angleScale()
    }

    private enum TrimArc {
        /// Provably one full revolution (only parameter values can show this).
        case full
        /// Trim ends coincide without parameter evidence: a turn of 0 or 2π cannot be told apart.
        case unknown
        /// Arc in the basis curve's direction, counterclockwise from `start`.
        case partial(start: Double, sweep: Double)
    }

    private func trimArc(_ trim: STEPTrimSpec, circle: STEPCircleGeometry, tolerance: Double) throws -> TrimArc {
        let first = try angle(of: trim.first, master: trim.master, circle: circle, tolerance: tolerance)
        let second = try angle(of: trim.second, master: trim.master, circle: circle, tolerance: tolerance)
        if let p1 = trim.first.parameter, let p2 = trim.second.parameter, let unit = try optionalAngleScale() {
            let span = abs(p2 - p1) * unit
            if abs(span - STEPAngle.twoPi) <= Self.angularTolerance { return .full }
            if span > STEPAngle.twoPi + Self.angularTolerance {
                throw STEPParseError("Trimmed circle spans more than one revolution")
            }
        }
        // sense_agreement FALSE runs trim_1 → trim_2 against the basis direction.
        let sweep = trim.senseAgreement ? STEPAngle.wrapped(second - first) : STEPAngle.wrapped(first - second)
        if sweep <= Self.angularTolerance || sweep >= STEPAngle.twoPi - Self.angularTolerance { return .unknown }
        return .partial(start: trim.senseAgreement ? first : second, sweep: sweep)
    }

    // MARK: Interval

    private struct ArcSpan {
        let start: Double
        /// Signed: negative runs against the basis direction. Always from the start vertex.
        let sweep: Double
        let isFull: Bool
    }

    private func arcSpan(circle: STEPCircleGeometry, trim: STEPTrimSpec?, start: SIMD3<Double>, end: SIMD3<Double>,
                         startVertexID: Int, endVertexID: Int, sameSense: Bool) throws -> ArcSpan {
        let tolerance = max(1e-4 * circle.radius, 1e-9 * (1 + simd_length(circle.frame.origin)))
        let a = circle.projection(of: start)
        let b = circle.projection(of: end)
        guard a.distance <= tolerance else {
            throw STEPParseError("Edge start vertex #\(startVertexID) is not on its circle (off by \(a.distance) mm)")
        }
        guard b.distance <= tolerance else {
            throw STEPParseError("Edge end vertex #\(endVertexID) is not on its circle (off by \(b.distance) mm)")
        }
        // start → end follows the edge curve when same_sense; the edge curve follows the
        // basis when the (optional) trim agrees. ORIENTED_EDGE plays no part here.
        let forward = sameSense == (trim?.senseAgreement ?? true)
        let arc = try trim.map { try trimArc($0, circle: circle, tolerance: tolerance) }

        let sameVertex = startVertexID == endVertexID
        if sameVertex || simd_distance(start, end) <= tolerance {
            if case .partial? = arc { throw STEPParseError("Closed edge, but its trimmed curve is a partial arc") }
            if !sameVertex {
                guard case .full? = arc else {
                    throw STEPParseError("Ambiguous edge: distinct vertices at the same point and nothing proves a full circle")
                }
            }
            return ArcSpan(start: a.angle, sweep: forward ? STEPAngle.twoPi : -STEPAngle.twoPi, isFull: true)
        }

        let magnitude = forward ? STEPAngle.wrapped(b.angle - a.angle) : STEPAngle.wrapped(a.angle - b.angle)
        guard magnitude > 1e-9 else { throw STEPParseError("Degenerate circular edge") }
        if let arc {
            guard case .partial(let trimStart, let trimSweep) = arc,
                  STEPAngle.distance(forward ? a.angle : b.angle, trimStart) <= Self.angularTolerance,
                  abs(magnitude - trimSweep) <= Self.angularTolerance else {
                throw STEPParseError("Edge vertices disagree with the trimmed curve")
            }
        }
        return ArcSpan(start: a.angle, sweep: forward ? magnitude : -magnitude, isFull: false)
    }
}
