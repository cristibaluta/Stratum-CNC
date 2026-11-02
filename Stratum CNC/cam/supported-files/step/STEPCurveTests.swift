import Testing
import Foundation
import simd
@testable import Stratum_CNC

// Fixtures are generated, topologically minimal Part 21 files: the extractor only walks
// body → shell → face → loop → oriented edge → edge, so an arc can sit alone in a loop.

private enum LengthUnit {
    case millimetre, metre, inch
}

private enum AngleUnit {
    case radian, degree, none
}

private final class StepBuilder {
    private var lines: [String] = []
    private var next = 1
    private let lengthUnit: LengthUnit
    private let angleUnit: AngleUnit

    init(length: LengthUnit = .millimetre, angle: AngleUnit = .radian) {
        lengthUnit = length
        angleUnit = angle
    }

    /// Part 21 reals need a decimal point; %E always gives one.
    static func real(_ value: Double) -> String { String(format: "%.15E", value) }
    static func triple(_ v: SIMD3<Double>) -> String { "(\(real(v.x)),\(real(v.y)),\(real(v.z)))" }

    @discardableResult
    func add(_ body: String) -> Int {
        let id = next
        next += 1
        lines.append("#\(id)=\(body);")
        return id
    }

    func point(_ p: SIMD3<Double>) -> Int { add("CARTESIAN_POINT('',\(Self.triple(p)))") }
    func vertex(_ p: SIMD3<Double>) -> Int { add("VERTEX_POINT('',#\(point(p)))") }
    func direction(_ d: SIMD3<Double>) -> Int { add("DIRECTION('',\(Self.triple(d)))") }

    func placement(origin: SIMD3<Double>, axis: SIMD3<Double>? = nil, ref: SIMD3<Double>? = nil) -> Int {
        let location = point(origin)
        let axisRef = axis.map { "#\(direction($0))" } ?? "$"
        let refRef = ref.map { "#\(direction($0))" } ?? "$"
        return add("AXIS2_PLACEMENT_3D('',#\(location),\(axisRef),\(refRef))")
    }

    func circle(placement: Int, radius: Double) -> Int {
        add("CIRCLE('',#\(placement),\(Self.real(radius)))")
    }

    func line(from p: SIMD3<Double>, direction d: SIMD3<Double>) -> Int {
        let vector = add("VECTOR('',#\(direction(d)),1.0E+00)")
        return add("LINE('',#\(point(p)),#\(vector))")
    }

    /// `first`/`second` are the raw trimming SETs, e.g. "(#12)" or "(PARAMETER_VALUE(0.5E+00))".
    func trimmed(basis: Int, first: String, second: String, senseAgreement: Bool, master: String) -> Int {
        add("TRIMMED_CURVE('',#\(basis),\(first),\(second),.\(senseAgreement ? "T" : "F").,.\(master).)")
    }

    func surfaceCurve(_ curve: Int, seam: Bool = false) -> Int {
        add("\(seam ? "SEAM_CURVE" : "SURFACE_CURVE")('',#\(curve),(),.CURVE_3D.)")
    }

    func edge(start: Int, end: Int, curve: Int, sameSense: Bool = true) -> Int {
        add("EDGE_CURVE('',#\(start),#\(end),#\(curve),.\(sameSense ? "T" : "F").)")
    }

    func ellipse(placement: Int, semiAxis1: Double, semiAxis2: Double) -> Int {
        add("ELLIPSE('',#\(placement),\(Self.real(semiAxis1)),\(Self.real(semiAxis2)))")
    }

    func polyline(_ points: [SIMD3<Double>]) -> Int {
        let ids = points.map { point($0) }
        return add("POLYLINE('',(\(ids.map { "#\($0)" }.joined(separator: ","))))")
    }

    /// Simple record when `weights` is nil, otherwise the complex rational record.
    func bspline(degree: Int, points: [SIMD3<Double>], weights: [Double]? = nil,
                 multiplicities: [Int], knots: [Double]) -> Int {
        let refs = "(" + points.map { "#\(point($0))" }.joined(separator: ",") + ")"
        let mults = "(" + multiplicities.map { String($0) }.joined(separator: ",") + ")"
        let knotList = "(" + knots.map { Self.real($0) }.joined(separator: ",") + ")"
        guard let weights else {
            return add("B_SPLINE_CURVE_WITH_KNOTS('',\(degree),\(refs),.UNSPECIFIED.,.F.,.F.,\(mults),\(knotList),.UNSPECIFIED.)")
        }
        let w = "(" + weights.map { Self.real($0) }.joined(separator: ",") + ")"
        return add("( BOUNDED_CURVE() B_SPLINE_CURVE(\(degree),\(refs),.UNSPECIFIED.,.F.,.F.) "
                   + "B_SPLINE_CURVE_WITH_KNOTS(\(mults),\(knotList),.UNSPECIFIED.) CURVE() "
                   + "GEOMETRIC_REPRESENTATION_ITEM() RATIONAL_B_SPLINE_CURVE(\(w)) REPRESENTATION_ITEM('') )")
    }

    typealias Use = (edge: Int, forward: Bool)
    static func fwd(_ edge: Int) -> Use { (edge, true) }
    static func rev(_ edge: Int) -> Use { (edge, false) }

    /// One face per loop.
    func data(loops: [[Use]]) -> Data {
        let surface = add("PLANE('',#\(placement(origin: .zero)))")
        var faces: [Int] = []
        for loop in loops {
            let uses = loop.map { add("ORIENTED_EDGE('',*,*,#\($0.edge),.\($0.forward ? "T" : "F").)") }
            let edgeLoop = add("EDGE_LOOP('',(\(uses.map { "#\($0)" }.joined(separator: ","))))")
            let bound = add("FACE_OUTER_BOUND('',#\(edgeLoop),.T.)")
            faces.append(add("ADVANCED_FACE('',(#\(bound)),#\(surface),.T.)"))
        }
        let shell = add("CLOSED_SHELL('',(\(faces.map { "#\($0)" }.joined(separator: ","))))")
        let solid = add("MANIFOLD_SOLID_BREP('',#\(shell))")
        let context = addContext()
        add("ADVANCED_BREP_SHAPE_REPRESENTATION('',(#\(solid)),#\(context))")

        return Data(("ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('curve test'),'2;1');\n"
            + "FILE_NAME('t.step','2026-01-01T00:00:00',(''),(''),'','','');\n"
            + "FILE_SCHEMA(('AUTOMOTIVE_DESIGN'));\nENDSEC;\nDATA;\n"
            + lines.joined(separator: "\n")
            + "\nENDSEC;\nEND-ISO-10303-21;\n").utf8)
    }

    private func addContext() -> Int {
        let millimetre = add("( LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.) )")
        let radian = add("( NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.) )")
        let dimensions = add("DIMENSIONAL_EXPONENTS(0.,0.,0.,0.,0.,0.,0.)")
        var units: [Int] = []
        switch lengthUnit {
            case .millimetre: units.append(millimetre)
            case .metre: units.append(add("( LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.) )"))
            case .inch:
                let measure = add("LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE(25.4),#\(millimetre))")
                units.append(add("( CONVERSION_BASED_UNIT('INCH',#\(measure)) LENGTH_UNIT() NAMED_UNIT(#\(dimensions)) )"))
        }
        switch angleUnit {
            case .radian: units.append(radian)
            case .degree:
                let measure = add("PLANE_ANGLE_MEASURE_WITH_UNIT(PLANE_ANGLE_MEASURE(0.017453292519943295),#\(radian))")
                units.append(add("( CONVERSION_BASED_UNIT('DEGREE',#\(measure)) NAMED_UNIT(#\(dimensions)) PLANE_ANGLE_UNIT() )"))
            case .none: break
        }
        let list = units.map { "#\($0)" }.joined(separator: ",")
        return add("( GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((\(list))) REPRESENTATION_CONTEXT('ctx','3D') )")
    }
}

// MARK: - Helpers

private func parse(_ data: Data, _ options: STEPImportOptions = STEPImportOptions()) throws -> STEPEdgeModel {
    try STEPEdgeImporter.parse(data: data, options: options)
}

/// Point on the standard XY circle about `center`.
private func onCircle(_ angle: Double, radius: Double = 5, center: SIMD3<Double> = .zero) -> SIMD3<Double> {
    center + SIMD3(radius * cos(angle), radius * sin(angle), 0)
}

private func near(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ tolerance: Double = 1e-9) -> Bool {
    simd_distance(a, b) <= tolerance
}

/// Largest gap between the true circle and the chords of `points`.
private func worstSagitta(_ points: [SIMD3<Double>], center: SIMD3<Double> = .zero, radius: Double) -> Double {
    zip(points, points.dropFirst()).map { radius - simd_distance(($0 + $1) / 2, center) }.max() ?? 0
}

/// A single circular edge from `startAngle` to `endAngle` on the standard XY circle.
private func singleArc(builder b: StepBuilder = StepBuilder(), from startAngle: Double, to endAngle: Double,
                       sameSense: Bool = true, radius: Double = 5,
                       curve: (StepBuilder, Int) -> Int = { _, circle in circle }) -> Data {
    let placement = b.placement(origin: .zero)
    let circle = b.circle(placement: placement, radius: radius)
    let start = b.vertex(onCircle(startAngle, radius: radius))
    let end = b.vertex(onCircle(endAngle, radius: radius))
    let edge = b.edge(start: start, end: end, curve: curve(b, circle), sameSense: sameSense)
    return b.data(loops: [[StepBuilder.fwd(edge)]])
}

// MARK: - Tests

@Suite("STEP circles and trims")
struct STEPCurveTests {

    @Test func cylinderHasTwoClosedCirclesAndASeam() throws {
        let b = StepBuilder()
        let bottomVertex = b.vertex(SIMD3(5, 0, 0))
        let topVertex = b.vertex(SIMD3(5, 0, 10))
        let bottomCircle = b.circle(placement: b.placement(origin: .zero), radius: 5)
        let topCircle = b.circle(placement: b.placement(origin: SIMD3(0, 0, 10)), radius: 5)
        let bottom = b.edge(start: bottomVertex, end: bottomVertex, curve: bottomCircle)
        let top = b.edge(start: topVertex, end: topVertex, curve: topCircle)
        let seam = b.edge(start: bottomVertex, end: topVertex, curve: b.line(from: SIMD3(5, 0, 0), direction: SIMD3(0, 0, 1)))
        let model = try parse(b.data(loops: [
            [StepBuilder.fwd(bottom)],
            [StepBuilder.fwd(top)],
            [StepBuilder.fwd(bottom), StepBuilder.fwd(seam), StepBuilder.rev(top), StepBuilder.rev(seam)]
        ]))

        #expect(model.edges.count == 3)
        #expect(model.reachableEdgeCount == 3 && model.skippedEdgeCount == 0)
        #expect(model.diagnostics.isEmpty)
        let circles = model.edges.filter { $0.kind == .circle }
        #expect(circles.count == 2)
        #expect(model.edges.filter { $0.kind == .line }.count == 1)

        for edge in circles {
            #expect(edge.points.count >= 9) // never fewer than an octagon
            #expect(near(edge.points.first!, edge.points.last!), "a closed circle must close")
            let z = edge.points[0].z
            for point in edge.points {
                #expect(abs(simd_length(SIMD2(point.x, point.y)) - 5) < 1e-9)
                #expect(abs(point.z - z) < 1e-12)
            }
            #expect(worstSagitta(edge.points, center: SIMD3(0, 0, z), radius: 5) <= 0.01 + 1e-9)
            #expect(edge.chordError <= 0.01)
            #expect(edge.adjacentFaceIDs.count == 2)
        }
        #expect(model.edges.first { $0.kind == .line }?.adjacentFaceIDs.count == 1)

        let bounds = try #require(model.bounds)
        #expect(near(bounds.min, SIMD3(-5, -5, 0), 1e-6) && near(bounds.max, SIMD3(5, 5, 10), 1e-6))
    }

    @Test func quarterArcMidpoint() throws {
        // A 1 mm tolerance forces the minimum resolution: two 45-degree segments.
        let model = try parse(singleArc(from: 0, to: .pi / 2), STEPImportOptions(chordToleranceMM: 1))
        let edge = try #require(model.edges.first)
        #expect(edge.kind == .arc)
        #expect(edge.points.count == 3)
        #expect(near(edge.points[0], SIMD3(5, 0, 0)))
        #expect(near(edge.points[1], SIMD3(5 * cos(.pi / 4), 5 * sin(.pi / 4), 0)))
        #expect(near(edge.points[2], SIMD3(0, 5, 0)))
    }

    @Test func defaultToleranceBoundsTheSagitta() throws {
        let edge = try #require(try parse(singleArc(from: 0, to: .pi / 2)).edges.first)
        #expect(worstSagitta(edge.points, radius: 5) <= 0.01 + 1e-9)
        #expect(edge.points.count > 3)
        #expect(near(edge.points.first!, SIMD3(5, 0, 0)) && near(edge.points.last!, SIMD3(0, 5, 0)))
    }

    @Test func sameSenseDecidesWhichArcIsMeant() throws {
        // Same two vertices; only same_sense differs. Along the circle's own direction
        // (counterclockwise) (0,5) → (5,0) is the long way round.
        let long = try #require(try parse(singleArc(from: .pi / 2, to: 0, sameSense: true)).edges.first)
        let short = try #require(try parse(singleArc(from: .pi / 2, to: 0, sameSense: false)).edges.first)

        #expect(long.points.contains { $0.x < -3 && $0.y < -3 }, "270 degrees must pass through the third quadrant")
        #expect(short.points.allSatisfy { $0.x > -1e-9 && $0.y > -1e-9 }, "90 degrees stays in the first quadrant")
        for edge in [long, short] {
            #expect(near(edge.points.first!, SIMD3(0, 5, 0)) && near(edge.points.last!, SIMD3(5, 0, 0)))
            #expect(edge.points.allSatisfy { abs(simd_length($0) - 5) < 1e-9 })
        }
        // ORIENTED_EDGE changes loop traversal, not the canonical edge.
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero), radius: 5)
        let edge = b.edge(start: b.vertex(onCircle(0)), end: b.vertex(onCircle(.pi / 2)), curve: circle)
        let flipped = try #require(try parse(b.data(loops: [[StepBuilder.rev(edge)]])).edges.first)
        #expect(near(flipped.points.first!, SIMD3(5, 0, 0)))
    }

    @Test func reversedFullCircleStartsClockwise() throws {
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero), radius: 5)
        let vertex = b.vertex(onCircle(0))
        let edge = b.edge(start: vertex, end: vertex, curve: circle, sameSense: false)
        let points = try #require(try parse(b.data(loops: [[StepBuilder.fwd(edge)]])).edges.first).points
        #expect(points[1].y < 0)
    }

    @Test func distinctVerticesAtOnePointAreNotAssumedToBeAFullCircle() throws {
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero), radius: 5)
        let edge = b.edge(start: b.vertex(onCircle(0)), end: b.vertex(onCircle(0)), curve: circle)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
        #expect(model.edges.isEmpty)
        #expect(model.skippedEdgeCount == 1)
        #expect(model.diagnostics.contains { $0.message.contains("Ambiguous") })
    }

    @Test func parameterTrimsProveAFullCircleOnDuplicateVertices() throws {
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero), radius: 5)
        let trimmed = b.trimmed(basis: circle, first: "(PARAMETER_VALUE(0.E+00))",
                                second: "(PARAMETER_VALUE(\(StepBuilder.real(2 * .pi))))",
                                senseAgreement: true, master: "PARAMETER")
        let edge = b.edge(start: b.vertex(onCircle(0)), end: b.vertex(onCircle(0)), curve: trimmed)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
        let result = try #require(model.edges.first)
        #expect(result.kind == .circle)
        #expect(result.points.count >= 9)
    }

    @Test func closedEdgeWithPartialTrimIsRejected() throws {
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero), radius: 5)
        let trimmed = b.trimmed(basis: circle, first: "(PARAMETER_VALUE(0.E+00))", second: "(PARAMETER_VALUE(1.E+00))",
                                senseAgreement: true, master: "PARAMETER")
        let vertex = b.vertex(onCircle(0))
        let edge = b.edge(start: vertex, end: vertex, curve: trimmed)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
        #expect(model.edges.isEmpty && model.diagnostics.contains { $0.message.contains("partial arc") })
    }

    // MARK: Frames

    @Test func defaultReferenceDirectionFollowsTheStandard() throws {
        // axis = +Y, no ref_direction: x = world Z, y = z × x = +X.
        let center = SIMD3<Double>(1, 2, 3)
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: center, axis: SIMD3(0, 1, 0)), radius: 5)
        let start = b.vertex(center + SIMD3(0, 0, 5))   // t = 0
        let end = b.vertex(center + SIMD3(5, 0, 0))     // t = π/2
        let edge = b.edge(start: start, end: end, curve: circle)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]), STEPImportOptions(chordToleranceMM: 1))
        let points = try #require(model.edges.first).points
        #expect(points.count == 3)
        #expect(near(points[1], center + SIMD3(5 * sin(.pi / 4), 0, 5 * cos(.pi / 4))))
    }

    @Test func missingAxisAndReferenceMeanTheWorldFrame() throws {
        let model = try parse(singleArc(from: 0, to: .pi / 2), STEPImportOptions(chordToleranceMM: 1))
        let points = try #require(model.edges.first).points
        #expect(near(points[1], SIMD3(5 / 2.0.squareRoot(), 5 / 2.0.squareRoot(), 0)))
    }

    @Test func referenceDirectionIsMadePerpendicularToTheAxis() throws {
        // ref (1,1,5) projects to (1,1,0)/√2, so t = 0 is on that diagonal.
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero, axis: SIMD3(0, 0, 1), ref: SIMD3(1, 1, 5)), radius: 5)
        let diagonal = SIMD3(1, 1, 0) / 2.0.squareRoot()
        let start = b.vertex(5 * diagonal)
        let end = b.vertex(SIMD3(-5, 5, 0) / 2.0.squareRoot())
        let edge = b.edge(start: start, end: end, curve: circle)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
        let points = try #require(model.edges.first).points
        #expect(near(points.first!, 5 * diagonal) && near(points.last!, SIMD3(-5, 5, 0) / 2.0.squareRoot()))
        #expect(points.allSatisfy { abs(simd_length($0) - 5) < 1e-9 && abs($0.z) < 1e-12 })
    }

    @Test func referenceDirectionParallelToTheAxisIsRejected() throws {
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero, axis: SIMD3(0, 0, 1), ref: SIMD3(0, 0, 3)), radius: 5)
        let vertex = b.vertex(SIMD3(5, 0, 0))
        let edge = b.edge(start: vertex, end: vertex, curve: circle)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
        #expect(model.edges.isEmpty && model.diagnostics.contains { $0.message.contains("Degenerate placement") })
    }

    @Test func vertexOffTheCircleIsRejected() throws {
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero), radius: 5)
        let edge = b.edge(start: b.vertex(SIMD3(5, 0, 0)), end: b.vertex(SIMD3(0, 5, 1)), curve: circle) // 1 mm above the plane
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
        #expect(model.edges.isEmpty && model.diagnostics.contains { $0.message.contains("not on its circle") })
    }

    // MARK: Trims

    /// The 90-degree arc written every supported way must come out identical.
    @Test(arguments: [
        TrimCase(name: "points", angle: .radian, first: { "(#\($0(0)))" }, second: { "(#\($0(.pi / 2)))" },
                 agree: true, master: "CARTESIAN", sameSense: true, reversedVertices: false),
        TrimCase(name: "radian parameters", angle: .radian, first: { _ in "(PARAMETER_VALUE(0.E+00))" },
                 second: { _ in "(PARAMETER_VALUE(\(StepBuilder.real(.pi / 2))))" },
                 agree: true, master: "PARAMETER", sameSense: true, reversedVertices: false),
        TrimCase(name: "degree parameters", angle: .degree, first: { _ in "(PARAMETER_VALUE(0.E+00))" },
                 second: { _ in "(PARAMETER_VALUE(9.E+01))" },
                 agree: true, master: "PARAMETER", sameSense: true, reversedVertices: false),
        TrimCase(name: "point and parameter", angle: .degree, first: { "(#\($0(0)))" },
                 second: { _ in "(PARAMETER_VALUE(9.E+01))" },
                 agree: true, master: "UNSPECIFIED", sameSense: true, reversedVertices: false),
        TrimCase(name: "both given, parameter master", angle: .degree,
                 first: { "(#\($0(0)),PARAMETER_VALUE(0.E+00))" }, second: { "(PARAMETER_VALUE(9.E+01),#\($0(.pi / 2)))" },
                 agree: true, master: "PARAMETER", sameSense: true, reversedVertices: false),
        // Trimmed curve runs π/2 → 0 against the basis direction; the edge follows it.
        TrimCase(name: "opposed sense, edge follows", angle: .radian, first: { "(#\($0(.pi / 2)))" }, second: { "(#\($0(0)))" },
                 agree: false, master: "CARTESIAN", sameSense: true, reversedVertices: true),
        // Same trimmed curve, edge runs against it: start → end is 0 → π/2 again.
        TrimCase(name: "opposed sense, edge reversed", angle: .radian, first: { "(#\($0(.pi / 2)))" }, second: { "(#\($0(0)))" },
                 agree: false, master: "CARTESIAN", sameSense: false, reversedVertices: false)
    ])
    func trimmedQuarterArc(_ trimCase: TrimCase) throws {
        let b = StepBuilder(angle: trimCase.angle)
        let circle = b.circle(placement: b.placement(origin: .zero), radius: 5)
        let pointAt: (Double) -> Int = { b.point(onCircle($0)) }
        let trimmed = b.trimmed(basis: circle, first: trimCase.first(pointAt), second: trimCase.second(pointAt),
                                senseAgreement: trimCase.agree, master: trimCase.master)
        let a = b.vertex(onCircle(0)), c = b.vertex(onCircle(.pi / 2))
        let (start, end) = trimCase.reversedVertices ? (c, a) : (a, c)
        let edge = b.edge(start: start, end: end, curve: trimmed, sameSense: trimCase.sameSense)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]), STEPImportOptions(chordToleranceMM: 1))

        let result = try #require(model.edges.first, "\(trimCase.name): \(model.diagnostics)")
        #expect(result.kind == .arc)
        #expect(result.points.count == 3, "\(trimCase.name)")
        let mid = SIMD3(5 * cos(Double.pi / 4), 5 * sin(Double.pi / 4), 0)
        #expect(near(result.points[1], mid), "\(trimCase.name)")
    }

    @Test func trimsThatContradictTheVerticesSkipTheEdge() throws {
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero), radius: 5)
        let trimmed = b.trimmed(basis: circle, first: "(#\(b.point(onCircle(0))))", second: "(#\(b.point(onCircle(.pi))))",
                                senseAgreement: true, master: "CARTESIAN")
        let edge = b.edge(start: b.vertex(onCircle(0)), end: b.vertex(onCircle(.pi / 2)), curve: trimmed)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
        #expect(model.edges.isEmpty && model.diagnostics.contains { $0.message.contains("disagree") })
    }

    @Test func parameterTrimsNeedAnAngleUnit() throws {
        let b = StepBuilder(angle: .none)
        let data = singleArc(builder: b, from: 0, to: .pi / 2) { b, circle in
            b.trimmed(basis: circle, first: "(PARAMETER_VALUE(0.E+00))", second: "(PARAMETER_VALUE(1.5E+00))",
                      senseAgreement: true, master: "PARAMETER")
        }
        let model = try parse(data)
        #expect(model.edges.isEmpty && model.diagnostics.contains { $0.message.contains("plane angle unit") })

        // Point trims never read the unit, so the same file shape still works with them.
        let pointB = StepBuilder(angle: .none)
        let ok = singleArc(builder: pointB, from: 0, to: .pi / 2) { b, circle in
            b.trimmed(basis: circle, first: "(#\(b.point(onCircle(0))))", second: "(#\(b.point(onCircle(.pi / 2))))",
                      senseAgreement: true, master: "CARTESIAN")
        }
        #expect(try parse(ok).edges.count == 1)
    }

    @Test func trimmedCircleInsideSurfaceAndSeamCurves() throws {
        for seam in [false, true] {
            let data = singleArc(from: 0, to: .pi / 2) { b, circle in
                let trimmed = b.trimmed(basis: circle, first: "(#\(b.point(onCircle(0))))",
                                        second: "(#\(b.point(onCircle(.pi / 2))))",
                                        senseAgreement: true, master: "CARTESIAN")
                return b.surfaceCurve(trimmed, seam: seam)
            }
            #expect(try parse(data).edges.first?.kind == .arc)
        }
    }

    @Test func trimmedLineStillUsesItsVertices() throws {
        let b = StepBuilder()
        let line = b.line(from: .zero, direction: SIMD3(1, 0, 0))
        let trimmed = b.trimmed(basis: line, first: "(PARAMETER_VALUE(0.E+00))", second: "(PARAMETER_VALUE(1.E+01))",
                                senseAgreement: true, master: "PARAMETER")
        let edge = b.edge(start: b.vertex(.zero), end: b.vertex(SIMD3(10, 0, 0)), curve: trimmed)
        let result = try #require(try parse(b.data(loops: [[StepBuilder.fwd(edge)]])).edges.first)
        #expect(result.kind == .line && result.points.count == 2)
    }

    // MARK: Units and sampling

    @Test func circleDimensionsAreScaledToMillimetres() throws {
        let b = StepBuilder(length: .inch)
        let model = try parse(singleArc(builder: b, from: 0, to: .pi / 2, radius: 1))
        let points = try #require(model.edges.first).points
        #expect(points.allSatisfy { abs(simd_length($0) - 25.4) < 1e-9 })
        #expect(near(points.first!, SIMD3(25.4, 0, 0)) && near(points.last!, SIMD3(0, 25.4, 0)))
        #expect(worstSagitta(points, radius: 25.4) <= 0.01 + 1e-9)
    }

    @Test func tinyRadiiStayRoundAndFinite() throws {
        for radius in [1e-3, 1e-6] {
            let b = StepBuilder()
            let circle = b.circle(placement: b.placement(origin: SIMD3(100, 0, 0)), radius: radius)
            let vertex = b.vertex(SIMD3(100 + radius, 0, 0))
            let edge = b.edge(start: vertex, end: vertex, curve: circle)
            let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
            let result = try #require(model.edges.first, "radius \(radius): \(model.diagnostics)")
            #expect(result.points.count == 9)
            #expect(result.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            #expect(result.chordError <= 0.01)
            #expect(model.diagnostics.isEmpty)
        }
    }

    @Test func hugeRadiusIsCappedAndReported() throws {
        let b = StepBuilder()
        let circle = b.circle(placement: b.placement(origin: .zero), radius: 1e6)
        let vertex = b.vertex(SIMD3(1e6, 0, 0))
        let edge = b.edge(start: vertex, end: vertex, curve: circle)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
        let result = try #require(model.edges.first)
        #expect(result.points.count == STEPArcSampler.maximumSegments + 1)
        #expect(result.chordError > 0.01)
        #expect(model.diagnostics.contains { $0.message.contains("exceeds") })
    }

    @Test func samplerUsesTheMinimumResolutionAndNeverOverflows() {
        #expect(STEPArcSampler.plan(radius: 5, sweep: .pi / 2, tolerance: 1).segments == 2)
        #expect(STEPArcSampler.plan(radius: 1e-9, sweep: 2 * .pi, tolerance: 0.01).segments == 8)
        #expect(STEPArcSampler.plan(radius: 1e300, sweep: 2 * .pi, tolerance: 0.01).segments == STEPArcSampler.maximumSegments)
    }

    @Test func chordToleranceMustBePositive() {
        for bad in [0.0, -1, .nan, .infinity] {
            #expect(throws: STEPParseError.self) {
                try parse(singleArc(from: 0, to: .pi / 2), STEPImportOptions(chordToleranceMM: bad))
            }
        }
    }

    @Test func unsupportedCurvesAreStillSkippedWithADiagnostic() throws {
        for (type, body) in [("PARABOLA", "PARABOLA('',#PLACEMENT,2.E+00)"),
                             ("HYPERBOLA", "HYPERBOLA('',#PLACEMENT,2.E+00,1.E+00)"),
                             ("QUASI_UNIFORM_CURVE", "QUASI_UNIFORM_CURVE('',2,(),.UNSPECIFIED.,.F.,.F.)")] {
            let b = StepBuilder()
            let curve = b.add(body.replacingOccurrences(of: "PLACEMENT", with: "\(b.placement(origin: .zero))"))
            let edge = b.edge(start: b.vertex(SIMD3(5, 0, 0)), end: b.vertex(SIMD3(0, 3, 0)), curve: curve)
            let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
            #expect(model.edges.isEmpty)
            #expect(model.diagnostics.contains { $0.message.contains("Unsupported curve \(type)") }, "\(type)")
        }
    }
}

struct TrimCase: Sendable, CustomTestStringConvertible {
    let name: String
    fileprivate let angle: AngleUnit
    /// Builds the trimming SET text; the closure argument creates a CARTESIAN_POINT on the circle.
    let first: @Sendable ((Double) -> Int) -> String
    let second: @Sendable ((Double) -> Int) -> String
    let agree: Bool
    let master: String
    let sameSense: Bool
    let reversedVertices: Bool
    var testDescription: String { name }
}

// MARK: - Step 4 helpers

/// One edge on a curve built by `curve`; `sameVertex` reuses the start vertex as the end.
private func singleEdge(_ b: StepBuilder = StepBuilder(), start: SIMD3<Double>, end: SIMD3<Double>,
                        sameSense: Bool = true, sameVertex: Bool = false,
                        curve: (StepBuilder) -> Int) -> Data {
    let curveID = curve(b)
    let startVertex = b.vertex(start)
    let endVertex = sameVertex ? startVertex : b.vertex(end)
    let edge = b.edge(start: startVertex, end: endVertex, curve: curveID, sameSense: sameSense)
    return b.data(loops: [[StepBuilder.fwd(edge)]])
}

/// Largest distance from a densely sampled true curve to the polyline that stands in for it.
private func deviation(of polyline: [SIMD3<Double>], from curve: (Double) -> SIMD3<Double>,
                       over range: ClosedRange<Double>, samples: Int = 1500) -> Double {
    var worst = 0.0
    for index in 0...samples {
        let t = range.lowerBound + (range.upperBound - range.lowerBound) * Double(index) / Double(samples)
        let target = curve(t)
        var best = Double.infinity
        for (a, b) in zip(polyline, polyline.dropFirst()) {
            best = min(best, STEPSegment.closest(to: target, a, b).distance)
        }
        worst = max(worst, best)
    }
    return worst
}

private let rationalWeight = 2.0.squareRoot() / 2

/// Quarter circle of radius 5 as a degree-2 rational B-spline: exactly round.
private func quarterCircle(_ b: StepBuilder) -> Int {
    b.bspline(degree: 2, points: [SIMD3(5, 0, 0), SIMD3(5, 5, 0), SIMD3(0, 5, 0)],
              weights: [1, rationalWeight, 1], multiplicities: [3, 3], knots: [0, 1])
}

/// Full circle of radius 5 as a closed, clamped, degree-2 rational B-spline starting at (5, 0).
private func fullCircle(_ b: StepBuilder) -> Int {
    b.bspline(degree: 2,
              points: [SIMD3(5, 0, 0), SIMD3(5, 5, 0), SIMD3(0, 5, 0), SIMD3(-5, 5, 0), SIMD3(-5, 0, 0),
                       SIMD3(-5, -5, 0), SIMD3(0, -5, 0), SIMD3(5, -5, 0), SIMD3(5, 0, 0)],
              weights: [1, rationalWeight, 1, rationalWeight, 1, rationalWeight, 1, rationalWeight, 1],
              multiplicities: [3, 2, 2, 2, 3], knots: [0, 0.25, 0.5, 0.75, 1])
}

private let bezierPoints = [SIMD3<Double>(0, 0, 0), SIMD3(10, 20, 0), SIMD3(30, 20, 0), SIMD3(40, 0, 0)]

private func bezier(_ t: Double) -> SIMD3<Double> {
    let u = 1 - t
    return u * u * u * bezierPoints[0] + 3 * u * u * t * bezierPoints[1]
        + 3 * u * t * t * bezierPoints[2] + t * t * t * bezierPoints[3]
}

private func cubicBezier(_ b: StepBuilder) -> Int {
    b.bspline(degree: 3, points: bezierPoints, multiplicities: [4, 4], knots: [0, 1])
}

private func ellipsePoint(_ t: Double, _ a: Double, _ b: Double) -> SIMD3<Double> { SIMD3(a * cos(t), b * sin(t), 0) }

// MARK: - Ellipses

@Suite("STEP ellipses")
struct STEPEllipseTests {

    @Test func fullEllipseStaysWithinTolerance() throws {
        let data = singleEdge(start: SIMD3(10, 0, 0), end: .zero, sameVertex: true) { b in
            b.ellipse(placement: b.placement(origin: .zero), semiAxis1: 10, semiAxis2: 5)
        }
        let edge = try #require(try parse(data).edges.first)
        #expect(edge.kind == .ellipse)
        #expect(near(edge.points.first!, edge.points.last!))
        #expect(edge.points.allSatisfy { abs($0.x * $0.x / 100 + $0.y * $0.y / 25 - 1) < 1e-9 && abs($0.z) < 1e-12 })
        #expect(edge.chordError <= 0.01 + 1e-9)
        #expect(deviation(of: edge.points, from: { ellipsePoint($0, 10, 5) }, over: 0...(2 * .pi)) <= 0.01 + 1e-6)
    }

    @Test func ellipticalArcUsesTheEdgeInterval() throws {
        // A 1 mm tolerance keeps the quarter at two segments, so the middle sample is t = π/4.
        let data = singleEdge(start: SIMD3(10, 0, 0), end: SIMD3(0, 5, 0)) { b in
            b.ellipse(placement: b.placement(origin: .zero), semiAxis1: 10, semiAxis2: 5)
        }
        let edge = try #require(try parse(data, STEPImportOptions(chordToleranceMM: 1)).edges.first)
        #expect(edge.kind == .ellipticalArc)
        #expect(edge.points.count == 3)
        #expect(near(edge.points[1], ellipsePoint(.pi / 4, 10, 5)))
        #expect(near(edge.points[0], SIMD3(10, 0, 0)) && near(edge.points[2], SIMD3(0, 5, 0)))
    }

    @Test func reversedEllipseTakesTheShortWayBack() throws {
        let data = singleEdge(start: SIMD3(0, 5, 0), end: SIMD3(10, 0, 0), sameSense: false) { b in
            b.ellipse(placement: b.placement(origin: .zero), semiAxis1: 10, semiAxis2: 5)
        }
        let edge = try #require(try parse(data).edges.first)
        #expect(edge.points.allSatisfy { $0.x > -1e-9 && $0.y > -1e-9 }, "stays in the first quadrant")
        #expect(near(edge.points.first!, SIMD3(0, 5, 0)) && near(edge.points.last!, SIMD3(10, 0, 0)))
    }

    @Test func semiAxisOneRunsAlongTheFrameX() throws {
        // (0, 10) lies on the 5 × 10 ellipse (x-axis 5, y-axis 10) but not on the 10 × 5 one.
        func edge(_ first: Double, _ second: Double) throws -> STEPEdgeModel {
            try parse(singleEdge(start: SIMD3(5, 0, 0), end: SIMD3(0, 10, 0)) { b in
                b.ellipse(placement: b.placement(origin: .zero), semiAxis1: first, semiAxis2: second)
            })
        }
        #expect(try edge(5, 10).edges.count == 1)
        let wrong = try edge(10, 5)
        #expect(wrong.edges.isEmpty && wrong.diagnostics.contains { $0.message.contains("not on its ellipse") })
    }

    @Test func parameterTrimsAreEllipseParameters() throws {
        // t = π/2 is (0, b), not the point at polar angle π/2 on a unit circle of radius a.
        let data = singleEdge(start: SIMD3(10, 0, 0), end: SIMD3(0, 5, 0)) { b in
            let ellipse = b.ellipse(placement: b.placement(origin: .zero), semiAxis1: 10, semiAxis2: 5)
            return b.trimmed(basis: ellipse, first: "(PARAMETER_VALUE(0.E+00))",
                             second: "(PARAMETER_VALUE(\(StepBuilder.real(.pi / 2))))",
                             senseAgreement: true, master: "PARAMETER")
        }
        #expect(try parse(data).edges.first?.kind == .ellipticalArc)
    }

    @Test func eccentricEllipseIsRefinedWhereItBends() throws {
        let data = singleEdge(start: SIMD3(50, 0, 0), end: .zero, sameVertex: true) { b in
            b.ellipse(placement: b.placement(origin: .zero), semiAxis1: 50, semiAxis2: 1)
        }
        let model = try parse(data)
        let edge = try #require(model.edges.first)
        #expect(model.diagnostics.isEmpty, "a probe-verified polygon must not trigger the tolerance warning")
        #expect(deviation(of: edge.points, from: { ellipsePoint($0, 50, 1) }, over: 0...(2 * .pi), samples: 4000) <= 0.01 + 1e-6)
    }
}

// MARK: - Polylines

@Suite("STEP polylines")
struct STEPPolylineTests {
    private let path = [SIMD3<Double>(0, 0, 0), SIMD3(10, 0, 0), SIMD3(10, 10, 0), SIMD3(20, 10, 0)]

    private func parseEdge(from start: SIMD3<Double>, to end: SIMD3<Double>, sameSense: Bool = true,
                           polyline: [SIMD3<Double>]? = nil) throws -> STEPEdgeModel {
        try parse(singleEdge(start: start, end: end, sameSense: sameSense) { $0.polyline(polyline ?? path) })
    }

    @Test func wholePolyline() throws {
        let edge = try #require(try parseEdge(from: path[0], to: path[3]).edges.first)
        #expect(edge.kind == .polyline)
        #expect(edge.points.count == 4)
        #expect(zip(edge.points, path).allSatisfy { near($0, $1) })
    }

    @Test func edgeIsCutOutOfTheMiddle() throws {
        let edge = try #require(try parseEdge(from: SIMD3(5, 0, 0), to: SIMD3(10, 5, 0)).edges.first)
        let expected = [SIMD3<Double>(5, 0, 0), SIMD3(10, 0, 0), SIMD3(10, 5, 0)]
        #expect(edge.points.count == 3 && zip(edge.points, expected).allSatisfy { near($0, $1) })
    }

    @Test func reversedSenseWalksBackwards() throws {
        let edge = try #require(try parseEdge(from: SIMD3(10, 5, 0), to: SIMD3(5, 0, 0), sameSense: false).edges.first)
        let expected = [SIMD3<Double>(10, 5, 0), SIMD3(10, 0, 0), SIMD3(5, 0, 0)]
        #expect(edge.points.count == 3 && zip(edge.points, expected).allSatisfy { near($0, $1) })
    }

    @Test func contradictoryDirectionAndOffCurveVerticesAreSkipped() throws {
        let backwards = try parseEdge(from: SIMD3(10, 5, 0), to: SIMD3(5, 0, 0))
        #expect(backwards.edges.isEmpty && backwards.diagnostics.contains { $0.message.contains("contradict") })
        let off = try parseEdge(from: SIMD3(5, 3, 0), to: path[3])
        #expect(off.edges.isEmpty && off.diagnostics.contains { $0.message.contains("not on its curve") })
    }

    @Test func closedPolylineWrapsAroundItsSeam() throws {
        let square = [SIMD3<Double>(0, 0, 0), SIMD3(10, 0, 0), SIMD3(10, 10, 0), SIMD3(0, 10, 0), SIMD3(0, 0, 0)]
        // (10,10) → (5,0) forward must continue past the seam: three corners, then back along the bottom.
        let edge = try #require(try parseEdge(from: SIMD3(10, 10, 0), to: SIMD3(5, 0, 0), polyline: square).edges.first)
        let expected = [SIMD3<Double>(10, 10, 0), SIMD3(0, 10, 0), SIMD3(0, 0, 0), SIMD3(5, 0, 0)]
        #expect(edge.points.count == 4 && zip(edge.points, expected).allSatisfy { near($0, $1) })

        let lap = try #require(try parse(singleEdge(start: square[0], end: square[0], sameVertex: true) { $0.polyline(square) }).edges.first)
        #expect(lap.points.count == 5 && near(lap.points.first!, lap.points.last!))
    }
}

// MARK: - B-splines

@Suite("STEP B-splines")
struct STEPBSplineTests {

    // MARK: Evaluation (independent closed forms)

    @Test func cubicBezierMatchesBernsteinForm() throws {
        let spline = try STEPBSpline(degree: 3, controlPoints: bezierPoints, weights: nil, multiplicities: [4, 4], knotValues: [0, 1])
        for t in stride(from: 0.0, through: 1.0, by: 0.125) {
            #expect(near(spline.point(at: t), bezier(t)))
        }
    }

    @Test func rationalQuarterCircleIsExactlyRound() throws {
        let spline = try STEPBSpline(degree: 2, controlPoints: [SIMD3(5, 0, 0), SIMD3(5, 5, 0), SIMD3(0, 5, 0)],
                                     weights: [1, rationalWeight, 1], multiplicities: [3, 3], knotValues: [0, 1])
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(abs(simd_length(spline.point(at: t)) - 5) < 1e-12)
        }
        #expect(near(spline.point(at: 0.5), SIMD3(5 * cos(.pi / 4), 5 * sin(.pi / 4), 0)))
    }

    @Test func interiorKnotsAndUnclampedKnotVectors() throws {
        // Interior knot of multiplicity 3 = degree: the curve passes through that control point.
        let c0 = try STEPBSpline(degree: 3,
                                 controlPoints: [SIMD3(0, 0, 0), SIMD3(1, 1, 0), SIMD3(2, -1, 0), SIMD3(3, 0, 0),
                                                 SIMD3(4, 1, 0), SIMD3(5, -1, 0), SIMD3(6, 0, 0)],
                                 weights: nil, multiplicities: [4, 3, 4], knotValues: [0, 1, 2])
        #expect(c0.domain == 0...2)
        #expect(near(c0.point(at: 0), SIMD3(0, 0, 0)) && near(c0.point(at: 1), SIMD3(3, 0, 0)) && near(c0.point(at: 2), SIMD3(6, 0, 0)))
        // Uniform knots 0...7, degree 2, five points: the domain is [2, 5] and the ends are midpoints.
        let open = try STEPBSpline(degree: 2,
                                   controlPoints: [SIMD3(0, 0, 0), SIMD3(1, 1, 0), SIMD3(2, 0, 0), SIMD3(3, 1, 0), SIMD3(4, 0, 0)],
                                   weights: nil, multiplicities: Array(repeating: 1, count: 8), knotValues: (0..<8).map { Double($0) })
        #expect(open.domain == 2...5)
        #expect(near(open.point(at: 2), SIMD3(0.5, 0.5, 0)) && near(open.point(at: 5), SIMD3(3.5, 0.5, 0)))
    }

    @Test func invalidSplinesAreRejected() {
        let points = Array(repeating: SIMD3<Double>(0, 0, 0), count: 6)
        func make(degree: Int = 3, count: Int = 4, weights: [Double]? = nil, mults: [Int] = [4, 4],
                  knots: [Double] = [0, 1]) throws -> STEPBSpline {
            try STEPBSpline(degree: degree, controlPoints: Array(points.prefix(count)), weights: weights,
                            multiplicities: mults, knotValues: knots)
        }
        #expect(throws: STEPParseError.self) { try make(degree: 0) }                       // degree
        #expect(throws: STEPParseError.self) { try make(count: 3, mults: [4, 3]) }         // too few points
        #expect(throws: STEPParseError.self) { try make(mults: [4, 3]) }                   // knot count
        #expect(throws: STEPParseError.self) { try make(mults: [4, 4], knots: [1, 1]) }    // not increasing
        #expect(throws: STEPParseError.self) { try make(knots: [1, 0]) }
        #expect(throws: STEPParseError.self) { try make(mults: [5, 3]) }                   // end multiplicity
        #expect(throws: STEPParseError.self) { try make(count: 5, mults: [4, 4, 4], knots: [0, 1, 2]) }
        #expect(throws: STEPParseError.self) { try make(weights: [1, 1, 0, 1]) }           // zero weight
        #expect(throws: STEPParseError.self) { try make(weights: [1, 1, 1]) }              // weight count
    }

    @Test func projectionFindsTheParameter() throws {
        let spline = try STEPBSpline(degree: 3, controlPoints: bezierPoints, weights: nil, multiplicities: [4, 4], knotValues: [0, 1])
        let hit = STEPBSplineProjector(spline).closest(to: bezier(0.3))
        #expect(abs(hit.t - 0.3) < 1e-6 && hit.distance < 1e-9)
    }

    // MARK: Sampling

    @Test func bezierEdgeFollowsTheCurve() throws {
        let data = singleEdge(start: bezierPoints[0], end: bezierPoints[3]) { cubicBezier($0) }
        let model = try parse(data)
        let edge = try #require(model.edges.first)
        #expect(edge.kind == .bspline && model.diagnostics.isEmpty)
        #expect(near(edge.points.first!, bezierPoints[0]) && near(edge.points.last!, bezierPoints[3]))
        let spline = try STEPBSpline(degree: 3, controlPoints: bezierPoints, weights: nil, multiplicities: [4, 4], knotValues: [0, 1])
        let projector = STEPBSplineProjector(spline)
        #expect(edge.points.allSatisfy { projector.closest(to: $0).distance < 1e-6 }, "every sample lies on the curve")
        #expect(deviation(of: edge.points, from: bezier, over: 0...1) <= 0.01 + 1e-6)
        #expect(edge.chordError <= 0.01)
    }

    @Test func sBendWhoseMidpointLiesOnTheChordIsNotMissed() throws {
        // Anti-symmetric control polygon: the t = 0.5 point is on the chord, so a midpoint-only
        // flatness test would accept the whole curve as one segment.
        let points = [SIMD3<Double>(0, 0, 0), SIMD3(10, 30, 0), SIMD3(20, -30, 0), SIMD3(30, 0, 0)]
        func s(_ t: Double) -> SIMD3<Double> {
            let u = 1 - t
            return u * u * u * points[0] + 3 * u * u * t * points[1] + 3 * u * t * t * points[2] + t * t * t * points[3]
        }
        #expect(near(s(0.5), SIMD3(15, 0, 0)))
        let data = singleEdge(start: points[0], end: points[3]) { b in
            b.bspline(degree: 3, points: points, multiplicities: [4, 4], knots: [0, 1])
        }
        let edge = try #require(try parse(data).edges.first)
        #expect(edge.points.count > 10)
        #expect(deviation(of: edge.points, from: s, over: 0...1) <= 0.01 + 1e-6)
    }

    @Test func rationalComplexRecordIsExactlyRound() throws {
        let data = singleEdge(start: SIMD3(5, 0, 0), end: SIMD3(0, 5, 0)) { quarterCircle($0) }
        let edge = try #require(try parse(data).edges.first)
        #expect(edge.kind == .bspline)
        #expect(edge.points.dropFirst().dropLast().allSatisfy { abs(simd_length($0) - 5) < 1e-9 })
        #expect(deviation(of: edge.points, from: { onCircle($0) }, over: 0...(.pi / 2)) <= 0.01 + 1e-6)
    }

    @Test func tightToleranceIsCappedAndReported() throws {
        let data = singleEdge(start: bezierPoints[0], end: bezierPoints[3]) { cubicBezier($0) }
        let model = try parse(data, STEPImportOptions(chordToleranceMM: 1e-9))
        let edge = try #require(model.edges.first)
        #expect(edge.points.count <= 25_000)
        #expect(model.diagnostics.contains { $0.message.contains("exceeds") })
    }

    // MARK: Edge intervals

    @Test func reversedSenseRunsFromTheCurveEnd() throws {
        let data = singleEdge(start: SIMD3(0, 5, 0), end: SIMD3(5, 0, 0), sameSense: false) { quarterCircle($0) }
        let edge = try #require(try parse(data).edges.first)
        #expect(near(edge.points.first!, SIMD3(0, 5, 0)) && near(edge.points.last!, SIMD3(5, 0, 0)))
        #expect(edge.points.count > 2)

        let backwards = try parse(singleEdge(start: SIMD3(0, 5, 0), end: SIMD3(5, 0, 0)) { quarterCircle($0) })
        #expect(backwards.edges.isEmpty && backwards.diagnostics.contains { $0.message.contains("contradict") })
    }

    @Test func midCurveVerticesAreFoundByProjection() throws {
        let t0 = 0.25, t1 = 0.75
        let data = singleEdge(start: bezier(t0), end: bezier(t1)) { cubicBezier($0) }
        let edge = try #require(try parse(data).edges.first)
        #expect(near(edge.points.first!, bezier(t0)) && near(edge.points.last!, bezier(t1)))
        #expect(deviation(of: edge.points, from: bezier, over: t0...t1) <= 0.01 + 1e-6)
        // Nothing beyond the edge's own interval: x grows monotonically for this curve.
        #expect(edge.points.allSatisfy { $0.x >= bezier(t0).x - 1e-6 && $0.x <= bezier(t1).x + 1e-6 })
    }

    @Test func closedSplineFullLapAndSeamHandling() throws {
        let seam = SIMD3<Double>(5, 0, 0)
        let top = SIMD3<Double>(0, 5, 0)

        let lap = try #require(try parse(singleEdge(start: seam, end: seam, sameVertex: true) { fullCircle($0) }).edges.first)
        #expect(near(lap.points.first!, lap.points.last!) && lap.points.count > 9)
        #expect(lap.points.dropFirst().dropLast().allSatisfy { abs(simd_length($0) - 5) < 1e-9 })

        // A → seam runs the long way (270°), and backwards only a quarter: the seam vertex is both
        // ends of the curve, so its role in the edge decides which one it is.
        let long = try #require(try parse(singleEdge(start: top, end: seam) { fullCircle($0) }).edges.first)
        #expect(long.points.contains { $0.x < -3 && $0.y < -3 })
        #expect(near(long.points.first!, top) && near(long.points.last!, seam))
        let short = try #require(try parse(singleEdge(start: top, end: seam, sameSense: false) { fullCircle($0) }).edges.first)
        #expect(short.points.allSatisfy { $0.x > -1e-9 && $0.y > -1e-9 })

        // The vertex halfway round a closed curve: a lap that starts and ends there.
        let midLap = try #require(try parse(singleEdge(start: top, end: top, sameVertex: true) { fullCircle($0) }).edges.first)
        #expect(near(midLap.points.first!, top) && near(midLap.points.last!, top))
        #expect(midLap.points.contains { near($0, seam, 1e-9) }, "the lap passes through the seam")
    }

    @Test func distinctVerticesAtTheSeamNeedProofOfAFullLap() throws {
        let seam = SIMD3<Double>(5, 0, 0)
        let ambiguous = try parse(singleEdge(start: seam, end: seam) { fullCircle($0) })
        #expect(ambiguous.edges.isEmpty && ambiguous.diagnostics.contains { $0.message.contains("Ambiguous") })

        let proven = try parse(singleEdge(start: seam, end: seam) { b in
            b.trimmed(basis: fullCircle(b), first: "(PARAMETER_VALUE(0.E+00))", second: "(PARAMETER_VALUE(1.E+00))",
                      senseAgreement: true, master: "PARAMETER")
        })
        #expect(proven.edges.first?.kind == .bspline)
    }

    @Test func openCurveRejectsCoincidentVerticesAndOffCurveVertices() throws {
        let same = try parse(singleEdge(start: bezier(0.5), end: bezier(0.5), sameVertex: true) { cubicBezier($0) })
        #expect(same.edges.isEmpty && same.diagnostics.contains { $0.message.contains("coincident") })
        let off = try parse(singleEdge(start: bezier(0.2) + SIMD3(0, 1, 0), end: bezier(0.8)) { cubicBezier($0) })
        #expect(off.edges.isEmpty && off.diagnostics.contains { $0.message.contains("not on its curve") })
    }

    // MARK: Wrappers and bad files

    @Test func wrappersAndOpposedTrimsAroundASpline() throws {
        // SURFACE_CURVE → TRIMMED_CURVE (sense FALSE) → spline: the edge follows the trim, so it
        // starts at the curve's end.
        func data(start: SIMD3<Double>, end: SIMD3<Double>) -> Data {
            singleEdge(start: start, end: end) { b in
                let trimmed = b.trimmed(basis: cubicBezier(b), first: "(PARAMETER_VALUE(1.E+00))",
                                        second: "(PARAMETER_VALUE(0.E+00))", senseAgreement: false, master: "PARAMETER")
                return b.surfaceCurve(trimmed)
            }
        }
        let ok = try #require(try parse(data(start: bezierPoints[3], end: bezierPoints[0])).edges.first)
        #expect(near(ok.points.first!, bezierPoints[3]) && near(ok.points.last!, bezierPoints[0]))
        #expect(try parse(data(start: bezierPoints[0], end: bezierPoints[3])).edges.isEmpty)
    }

    @Test func malformedSplinesAreSkippedWithADiagnostic() throws {
        let data = singleEdge(start: bezierPoints[0], end: bezierPoints[3]) { b in
            // Degree 3 with four points needs eight knots; the multiplicities give seven.
            b.bspline(degree: 3, points: bezierPoints, multiplicities: [4, 3], knots: [0, 1])
        }
        let model = try parse(data)
        #expect(model.edges.isEmpty && model.diagnostics.contains { $0.message.contains("knots") })
    }
}
