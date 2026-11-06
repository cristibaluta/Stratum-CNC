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

/// Circle (entity CIRCLE) or ellipse in its own frame:
/// P(t) = origin + semiAxisX·cos t·x + semiAxisY·sin t·y, for t in one 2π period.
struct STEPConicGeometry {
    let frame: STEPFrame
    let semiAxisX: Double // mm, along frame.x
    let semiAxisY: Double // mm, along frame.y
    let isEllipse: Bool   // which entity it came from, not the axis ratio

    var noun: String { isEllipse ? "ellipse" : "circle" }
    var largestAxis: Double { max(semiAxisX, semiAxisY) }

    func point(at angle: Double) -> SIMD3<Double> {
        frame.origin + semiAxisX * cos(angle) * frame.x + semiAxisY * sin(angle) * frame.y
    }

    /// Parameter of `point` and how far it is from the curve (out-of-plane offset included).
    /// Exact for points on the curve; off-curve points only need to be reported as far away.
    func projection(of point: SIMD3<Double>) -> (angle: Double, distance: Double) {
        let offset = point - frame.origin
        let angle = atan2(simd_dot(offset, frame.y) / semiAxisY, simd_dot(offset, frame.x) / semiAxisX)
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

/// Parameter-space refinement shared by ellipses and B-splines. Midpoint flatness alone accepts
/// S-bends whose midpoint lies on the chord, so each piece is judged by probes at 1/4, 1/2 and
/// 3/4. Splits are bounded in depth and in total points; `limited` reports a bound that bit.
enum STEPAdaptiveSampler {
    struct Sampling {
        let points: [SIMD3<Double>]
        /// Largest probed distance between a final chord and the curve (mm).
        let deviation: Double
        /// True if the point budget or depth limit stopped refinement above tolerance.
        let limited: Bool
    }

    /// `parameters` are the starting breakpoints, ascending or descending; the output follows
    /// their order and always contains every one of them.
    static func sample(parameters: [Double], tolerance: Double, pointBudget: Int, maximumDepth: Int = 12,
                       point: (Double) -> SIMD3<Double>) -> Sampling {
        struct Piece {
            let ta: Double, pa: SIMD3<Double>, tb: Double, pb: SIMD3<Double>, depth: Int
        }
        let budget = max(pointBudget, parameters.count * 2)
        var output = [point(parameters[0])]
        var deviation = 0.0
        var limited = false
        var previous = output[0]
        for index in 1..<parameters.count {
            let end = point(parameters[index])
            var stack = [Piece(ta: parameters[index - 1], pa: previous, tb: parameters[index], pb: end, depth: 0)]
            while let piece = stack.popLast() {
                let width = piece.tb - piece.ta
                var worst = 0.0
                for fraction in [0.25, 0.5, 0.75] {
                    let probe = point(piece.ta + width * fraction)
                    worst = max(worst, STEPSegment.closest(to: probe, piece.pa, piece.pb).distance)
                }
                if worst <= tolerance || abs(width) <= 1e-12 * max(1, abs(piece.tb)) {
                    output.append(piece.pb)
                    deviation = max(deviation, worst)
                } else if piece.depth >= maximumDepth || output.count + stack.count + 2 > budget {
                    output.append(piece.pb)
                    deviation = max(deviation, worst)
                    limited = true
                } else {
                    let middle = piece.ta + width / 2
                    let pm = point(middle)
                    stack.append(Piece(ta: middle, pa: pm, tb: piece.tb, pb: piece.pb, depth: piece.depth + 1))
                    stack.append(Piece(ta: piece.ta, pa: piece.pa, tb: middle, pb: pm, depth: piece.depth + 1))
                }
            }
            previous = end
        }
        return Sampling(points: output, deviation: deviation, limited: limited)
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

    private struct EdgeEnds {
        let startVertexID: Int
        let endVertexID: Int
        let start: SIMD3<Double>
        let end: SIMD3<Double>
        /// Whether start → end runs along the edge curve's own direction.
        let sameSense: Bool
    }

    private func edgeEnds(_ startVertexID: Int, _ endVertexID: Int, sameSense: Bool) throws -> EdgeEnds {
        EdgeEnds(startVertexID: startVertexID, endVertexID: endVertexID,
                 start: try vertex(startVertexID), end: try vertex(endVertexID), sameSense: sameSense)
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
        if file.hasType(basisID, "CIRCLE") || file.hasType(basisID, "ELLIPSE") {
            let conic = try conicGeometry(basisID)
            let trim = try trimParameters.map { try trimSpec($0) }
            let ends = try edgeEnds(startVertexID, endVertexID, sameSense: sameSense)
            return try resolveConic(conic, trim: trim, ends: ends)
        }
        if file.hasType(basisID, "POLYLINE") {
            let polyline = try polylineGeometry(basisID)
            let trim = try trimParameters.map { try trimSpec($0) }
            let ends = try edgeEnds(startVertexID, endVertexID, sameSense: sameSense)
            return try resolvePolyline(polyline, trim: trim, ends: ends)
        }
        if file.hasType(basisID, "B_SPLINE_CURVE_WITH_KNOTS") {
            let spline = try splineGeometry(basisID)
            let trim = try trimParameters.map { try trimSpec($0) }
            let ends = try edgeEnds(startVertexID, endVertexID, sameSense: sameSense)
            return try resolveSpline(spline, trim: trim, ends: ends)
        }
        let names = try file.components(basisID).map(\.type).joined(separator: "/")
        throw STEPParseError("Unsupported curve \(names) at #\(basisID); edge skipped")
    }

    // MARK: Conics

    private func resolveConic(_ conic: STEPConicGeometry, trim: STEPTrimSpec?, ends: EdgeEnds) throws -> STEPResolvedCurve {
        let span = try arcSpan(conic: conic, trim: trim, ends: ends)
        var points: [SIMD3<Double>]
        let chordError: Double
        let exceeded: Bool
        let major = conic.largestAxis
        if abs(conic.semiAxisX - conic.semiAxisY) <= 1e-12 * major {
            // Circle: the sagitta of an equal-step polygon is known exactly.
            let plan = STEPArcSampler.plan(radius: major, sweep: span.sweep, tolerance: chordTolerance)
            points = (0...plan.segments).map {
                conic.point(at: span.start + span.sweep * Double($0) / Double(plan.segments))
            }
            chordError = plan.chordError
            exceeded = plan.chordError > chordTolerance * (1 + 1e-9)
        } else {
            // Ellipse: start from steps a circle of the major radius would accept, then let
            // probes refine where curvature is high.
            let step = min((8 * chordTolerance / major).squareRoot(), STEPArcSampler.maximumAngularStep)
            let wanted = step > 0 ? (abs(span.sweep) / step - 1e-9).rounded(.up) : Double.infinity
            let count = Int(min(max(wanted, 2), Double(STEPArcSampler.maximumSegments)))
            let parameters = (0...count).map { span.start + span.sweep * Double($0) / Double(count) }
            let sampling = STEPAdaptiveSampler.sample(parameters: parameters, tolerance: chordTolerance,
                                                      pointBudget: STEPArcSampler.maximumSegments + 1) { conic.point(at: $0) }
            points = sampling.points
            chordError = sampling.deviation
            exceeded = sampling.limited && sampling.deviation > chordTolerance * (1 + 1e-9)
        }
        points[0] = ends.start
        points[points.count - 1] = ends.end
        guard points.allSatisfy({ point in (0..<3).allSatisfy { point[$0].isFinite } }) else {
            throw STEPParseError("Nonfinite sampled \(conic.noun) points")
        }
        var warning: String?
        if exceeded {
            warning = String(format: "Edge approximated with %ld segments; chord error %.3g mm exceeds the %.3g mm tolerance",
                             points.count - 1, chordError, chordTolerance)
        }
        let kind: STEPEdge.CurveKind
        switch (conic.isEllipse, span.isFull) {
            case (false, true): kind = .circle
            case (false, false): kind = .arc
            case (true, true): kind = .ellipse
            case (true, false): kind = .ellipticalArc
        }
        return STEPResolvedCurve(kind: kind, points: points, chordError: chordError, warning: warning)
    }

    // MARK: Bounded curves (polylines, B-splines)

    /// One directed run through the parameter domain; `to < from` runs backwards.
    private struct Piece {
        let from: Double
        let to: Double
    }

    /// Relative vertex tolerance for curves that carry no natural scale of their own.
    private static let relativeVertexTolerance = 1e-4

    private func boundedTolerance(_ points: [SIMD3<Double>]) -> Double {
        var low = points[0]
        var high = points[0]
        for point in points {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        var magnitude = 0.0
        for axis in 0..<3 { magnitude = max(magnitude, abs(low[axis]), abs(high[axis])) }
        return max(Self.relativeVertexTolerance * simd_length(high - low), 1e-9 * (1 + magnitude), 1e-7)
    }

    /// Splits the edge into directed runs of the curve's parameter domain.
    ///
    /// The vertices define the extent; trims on these curves contribute only their direction
    /// (`sense_agreement`) and, for B-splines, proof that a closed edge covers the whole curve.
    /// A vertex at the start of a closed curve is also at its end, so such a vertex takes the
    /// end its role needs: an edge's start vertex begins its own traversal.
    private func boundedPieces(domain: ClosedRange<Double>, curveStart: SIMD3<Double>, curveEnd: SIMD3<Double>,
                               trim: STEPTrimSpec?, trimCoversDomain: Bool, ends: EdgeEnds, tolerance: Double,
                               project: (SIMD3<Double>) -> (t: Double, distance: Double)) throws -> [Piece] {
        let low = domain.lowerBound
        let high = domain.upperBound
        let epsilon = 1e-9 * (high - low)
        let closed = simd_distance(curveStart, curveEnd) <= tolerance
        let forward = ends.sameSense == (trim?.senseAgreement ?? true)

        func parameter(of point: SIMD3<Double>, isStart: Bool, vertexID: Int) throws -> Double {
            let atLow = simd_distance(point, curveStart) <= tolerance
            let atHigh = simd_distance(point, curveEnd) <= tolerance
            if atLow && atHigh { return isStart == forward ? low : high }
            if atLow { return low }
            if atHigh { return high }
            let result = project(point)
            guard result.distance <= tolerance else {
                throw STEPParseError("Edge \(isStart ? "start" : "end") vertex #\(vertexID) is not on its curve (off by \(result.distance) mm)")
            }
            return result.t
        }
        func nonEmpty(_ pieces: [Piece]) -> [Piece] { pieces.filter { abs($0.to - $0.from) > epsilon } }

        let sameVertex = ends.startVertexID == ends.endVertexID
        if sameVertex || simd_distance(ends.start, ends.end) <= tolerance {
            guard closed else { throw STEPParseError("Edge has coincident vertices on an open curve") }
            if !sameVertex && !trimCoversDomain {
                throw STEPParseError("Ambiguous edge: distinct vertices at the same point and nothing proves the whole closed curve")
            }
            // One full lap from the vertex, wherever on the closed curve it sits.
            let t = try parameter(of: ends.start, isStart: true, vertexID: ends.startVertexID)
            return forward ? nonEmpty([Piece(from: t, to: high), Piece(from: low, to: t)])
                           : nonEmpty([Piece(from: t, to: low), Piece(from: high, to: t)])
        }

        let a = try parameter(of: ends.start, isStart: true, vertexID: ends.startVertexID)
        let b = try parameter(of: ends.end, isStart: false, vertexID: ends.endVertexID)
        if forward {
            if a < b - epsilon { return [Piece(from: a, to: b)] }
            guard closed else { throw STEPParseError("Edge vertices contradict the curve direction") }
            return nonEmpty([Piece(from: a, to: high), Piece(from: low, to: b)])
        }
        if a > b + epsilon { return [Piece(from: a, to: b)] }
        guard closed else { throw STEPParseError("Edge vertices contradict the curve direction") }
        return nonEmpty([Piece(from: a, to: low), Piece(from: high, to: b)])
    }

    /// Joins directed runs of points, dropping the repeated point where runs meet.
    private func joined(_ runs: [[SIMD3<Double>]]) -> [SIMD3<Double>] {
        var result: [SIMD3<Double>] = []
        for run in runs {
            result.append(contentsOf: result.isEmpty ? run[...] : run.dropFirst())
        }
        return result
    }

    private static let maximumEdgePoints = 20_000

    // MARK: Polylines

    private struct Polyline {
        let points: [SIMD3<Double>]
        var domain: ClosedRange<Double> { 0...Double(points.count - 1) }

        func point(at s: Double) -> SIMD3<Double> {
            let clamped = min(max(s, 0), Double(points.count - 1))
            let index = min(Int(clamped.rounded(.down)), points.count - 2)
            let u = clamped - Double(index)
            return points[index] + (points[index + 1] - points[index]) * u
        }

        func closest(to target: SIMD3<Double>) -> (t: Double, distance: Double) {
            var best = (t: 0.0, distance: Double.infinity)
            for index in 0..<(points.count - 1) {
                let hit = STEPSegment.closest(to: target, points[index], points[index + 1])
                if hit.distance < best.distance { best = (Double(index) + hit.u, hit.distance) }
            }
            return best
        }

        /// Ascending run of [from, to]: both ends plus every vertex strictly between.
        func run(from: Double, to: Double) -> [SIMD3<Double>] {
            var result = [point(at: from)]
            let first = Int(from.rounded(.down)) + 1
            let last = Int(to.rounded(.up)) - 1
            if first <= last {
                for index in first...last where Double(index) > from + 1e-12 && Double(index) < to - 1e-12 {
                    result.append(points[index])
                }
            }
            result.append(point(at: to))
            return result
        }
    }

    private func polylineGeometry(_ id: Int) throws -> Polyline {
        let ids = try file.parameters(id, type: "POLYLINE").references(at: 1)
        guard (2...Self.maximumEdgePoints).contains(ids.count) else {
            throw STEPParseError("Polyline #\(id) needs 2...\(Self.maximumEdgePoints) points, found \(ids.count)")
        }
        return Polyline(points: try ids.map { try cartesianPoint($0) })
    }

    private func resolvePolyline(_ polyline: Polyline, trim: STEPTrimSpec?, ends: EdgeEnds) throws -> STEPResolvedCurve {
        let tolerance = boundedTolerance(polyline.points)
        let pieces = try boundedPieces(domain: polyline.domain, curveStart: polyline.points[0], curveEnd: polyline.points[polyline.points.count - 1],
                                       trim: trim, trimCoversDomain: false, ends: ends, tolerance: tolerance,
                                       project: { polyline.closest(to: $0) })
        let runs = pieces.map { piece -> [SIMD3<Double>] in
            piece.from <= piece.to ? polyline.run(from: piece.from, to: piece.to)
                                   : Array(polyline.run(from: piece.to, to: piece.from).reversed())
        }
        var points = joined(runs)
        guard points.count >= 2 else { throw STEPParseError("Degenerate polyline edge") }
        points[0] = ends.start
        points[points.count - 1] = ends.end
        return STEPResolvedCurve(kind: .polyline, points: points, chordError: 0, warning: nil)
    }

    // MARK: B-splines

    private func integer(_ value: STEPValue) throws -> Int {
        guard case .integer(let result) = value else { throw STEPParseError("Expected an integer in B-spline data") }
        return result
    }

    private func numbers(_ value: STEPValue) throws -> [Double] {
        guard let items = value.list else { throw STEPParseError("Expected a list of numbers in B-spline data") }
        return try items.map {
            guard let number = $0.number, number.isFinite else { throw STEPParseError("Nonfinite B-spline number") }
            return number
        }
    }

    /// Both file layouts: the simple B_SPLINE_CURVE_WITH_KNOTS record, and the complex record
    /// of B_SPLINE_CURVE + B_SPLINE_CURVE_WITH_KNOTS (+ RATIONAL_B_SPLINE_CURVE for weights).
    private func splineGeometry(_ id: Int) throws -> STEPBSpline {
        let parts = try file.components(id)
        let degree: Int
        let controlIDs: [Int]
        let multiplicities: [STEPValue]
        let knots: [Double]
        var weights: [Double]?
        if let base = parts.first(where: { $0.type == "B_SPLINE_CURVE" }),
           let withKnots = parts.first(where: { $0.type == "B_SPLINE_CURVE_WITH_KNOTS" }) {
            degree = try integer(base.parameters.argument(0))
            controlIDs = try base.parameters.references(at: 1)
            guard let list = try withKnots.parameters.argument(0).list else { throw STEPParseError("Expected knot multiplicities") }
            multiplicities = list
            knots = try numbers(withKnots.parameters.argument(1))
            if let rational = parts.first(where: { $0.type == "RATIONAL_B_SPLINE_CURVE" }) {
                weights = try numbers(rational.parameters.argument(0))
            }
        } else if let simple = parts.first(where: { $0.type == "B_SPLINE_CURVE_WITH_KNOTS" }), simple.parameters.count == 9 {
            degree = try integer(simple.parameters.argument(1))
            controlIDs = try simple.parameters.references(at: 2)
            guard let list = try simple.parameters.argument(6).list else { throw STEPParseError("Expected knot multiplicities") }
            multiplicities = list
            knots = try numbers(simple.parameters.argument(7))
        } else {
            throw STEPParseError("Unsupported B-spline layout at #\(id)")
        }
        guard controlIDs.count <= STEPBSpline.maximumControlPoints else {
            throw STEPParseError("B-spline #\(id) has too many control points")
        }
        return try STEPBSpline(degree: degree,
                               controlPoints: try controlIDs.map { try cartesianPoint($0) },
                               weights: weights,
                               multiplicities: try multiplicities.map { try integer($0) },
                               knotValues: knots)
    }

    private func resolveSpline(_ spline: STEPBSpline, trim: STEPTrimSpec?, ends: EdgeEnds) throws -> STEPResolvedCurve {
        let domain = spline.domain
        let tolerance = boundedTolerance(spline.controlPoints)
        var projector: STEPBSplineProjector?
        var coversDomain = false
        if let p1 = trim?.first.parameter, let p2 = trim?.second.parameter {
            coversDomain = abs(abs(p2 - p1) - (domain.upperBound - domain.lowerBound)) <= 1e-6 * (domain.upperBound - domain.lowerBound)
        }
        let pieces = try boundedPieces(domain: domain, curveStart: spline.point(at: domain.lowerBound),
                                       curveEnd: spline.point(at: domain.upperBound),
                                       trim: trim, trimCoversDomain: coversDomain, ends: ends, tolerance: tolerance,
                                       project: { target in
                                           if projector == nil { projector = STEPBSplineProjector(spline) }
                                           return projector!.closest(to: target)
                                       })
        var runs: [[SIMD3<Double>]] = []
        var deviation = 0.0
        var limited = false
        var budget = Self.maximumEdgePoints
        for piece in pieces {
            try Task.checkCancellation()
            let low = min(piece.from, piece.to)
            let high = max(piece.from, piece.to)
            let sampling = spline.sample(from: low, to: high, tolerance: chordTolerance, pointBudget: max(budget, 64))
            runs.append(piece.from <= piece.to ? sampling.points : Array(sampling.points.reversed()))
            deviation = max(deviation, sampling.deviation)
            limited = limited || sampling.limited
            budget -= sampling.points.count
        }
        var points = joined(runs)
        guard points.count >= 2 else { throw STEPParseError("Degenerate B-spline edge") }
        points[0] = ends.start
        points[points.count - 1] = ends.end
        guard points.allSatisfy({ point in (0..<3).allSatisfy { point[$0].isFinite } }) else {
            throw STEPParseError("Nonfinite sampled B-spline points")
        }
        var warning: String?
        if limited || deviation > chordTolerance * (1 + 1e-9) {
            warning = String(format: "B-spline approximated with %ld points; probed chord error %.3g mm exceeds the %.3g mm tolerance",
                             points.count, deviation, chordTolerance)
        }
        return STEPResolvedCurve(kind: .bspline, points: points, chordError: deviation, warning: warning)
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
    func frame(_ id: Int) throws -> STEPFrame {
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

    private func conicGeometry(_ id: Int) throws -> STEPConicGeometry {
        let isEllipse = file.hasType(id, "ELLIPSE")
        let p = try file.parameters(id, type: isEllipse ? "ELLIPSE" : "CIRCLE")
        let frame = try frame(p.reference(at: 1))
        func axis(_ index: Int) throws -> Double {
            guard let length = try p.argument(index).number, length.isFinite, length > 0,
                  (length * scale).isFinite, length * scale > 0 else {
                throw STEPParseError("Invalid \(isEllipse ? "ellipse semi-axis" : "circle radius") at #\(id)")
            }
            return length * scale
        }
        let first = try axis(2)
        return STEPConicGeometry(frame: frame, semiAxisX: first, semiAxisY: isEllipse ? try axis(3) : first,
                                 isEllipse: isEllipse)
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
                       conic: STEPConicGeometry, tolerance: Double) throws -> Double {
        let usePoint: Bool
        switch master {
            case .parameter: usePoint = bound.parameter == nil
            case .cartesian, .unspecified: usePoint = bound.point != nil
        }
        if usePoint {
            guard let point = bound.point else { throw STEPParseError("Trim has neither point nor parameter") }
            let projection = conic.projection(of: point)
            guard projection.distance <= tolerance else { throw STEPParseError("Trim point is not on the \(conic.noun)") }
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

    private func trimArc(_ trim: STEPTrimSpec, conic: STEPConicGeometry, tolerance: Double) throws -> TrimArc {
        let first = try angle(of: trim.first, master: trim.master, conic: conic, tolerance: tolerance)
        let second = try angle(of: trim.second, master: trim.master, conic: conic, tolerance: tolerance)
        if let p1 = trim.first.parameter, let p2 = trim.second.parameter, let unit = try optionalAngleScale() {
            let span = abs(p2 - p1) * unit
            if abs(span - STEPAngle.twoPi) <= Self.angularTolerance { return .full }
            if span > STEPAngle.twoPi + Self.angularTolerance {
                throw STEPParseError("Trimmed \(conic.noun) spans more than one revolution")
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

    private func arcSpan(conic: STEPConicGeometry, trim: STEPTrimSpec?, ends: EdgeEnds) throws -> ArcSpan {
        let tolerance = max(1e-4 * conic.largestAxis, 1e-9 * (1 + simd_length(conic.frame.origin)))
        let a = conic.projection(of: ends.start)
        let b = conic.projection(of: ends.end)
        guard a.distance <= tolerance else {
            throw STEPParseError("Edge start vertex #\(ends.startVertexID) is not on its \(conic.noun) (off by \(a.distance) mm)")
        }
        guard b.distance <= tolerance else {
            throw STEPParseError("Edge end vertex #\(ends.endVertexID) is not on its \(conic.noun) (off by \(b.distance) mm)")
        }
        // start → end follows the edge curve when same_sense; the edge curve follows the
        // basis when the (optional) trim agrees. ORIENTED_EDGE plays no part here.
        let forward = ends.sameSense == (trim?.senseAgreement ?? true)
        let arc = try trim.map { try trimArc($0, conic: conic, tolerance: tolerance) }

        let sameVertex = ends.startVertexID == ends.endVertexID
        if sameVertex || simd_distance(ends.start, ends.end) <= tolerance {
            if case .partial? = arc { throw STEPParseError("Closed edge, but its trimmed curve is a partial arc") }
            if !sameVertex {
                guard case .full? = arc else {
                    throw STEPParseError("Ambiguous edge: distinct vertices at the same point and nothing proves a full \(conic.noun)")
                }
            }
            return ArcSpan(start: a.angle, sweep: forward ? STEPAngle.twoPi : -STEPAngle.twoPi, isFull: true)
        }

        let magnitude = forward ? STEPAngle.wrapped(b.angle - a.angle) : STEPAngle.wrapped(a.angle - b.angle)
        guard magnitude > 1e-9 else { throw STEPParseError("Degenerate \(conic.noun) edge") }
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
