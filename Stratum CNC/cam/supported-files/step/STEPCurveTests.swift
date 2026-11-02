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

    @Test func otherCurvesAreStillSkippedWithADiagnostic() throws {
        let b = StepBuilder()
        let ellipse = b.add("ELLIPSE('',#\(b.placement(origin: .zero)),5.E+00,3.E+00)")
        let edge = b.edge(start: b.vertex(SIMD3(5, 0, 0)), end: b.vertex(SIMD3(0, 3, 0)), curve: ellipse)
        let model = try parse(b.data(loops: [[StepBuilder.fwd(edge)]]))
        #expect(model.edges.isEmpty)
        #expect(model.diagnostics.contains { $0.message.contains("Unsupported curve ELLIPSE") })
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
