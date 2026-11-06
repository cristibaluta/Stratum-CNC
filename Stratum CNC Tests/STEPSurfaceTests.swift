import Foundation
import Testing
import simd
@testable import Stratum_CNC

// MARK: - Generated Part 21 solids with real surfaces

/// Builds small but complete B-reps: boxes (optionally with a through hole), cylinders and
/// open shells for a sphere band and a cone frustum. Generated, not CAD exports.
private final class SolidBuilder {
    private var lines: [String] = []
    private var next = 1
    private var vertexPoints: [Int: SIMD3<Double>] = [:]

    static func real(_ value: Double) -> String { String(format: "%.15E", value) }
    static func triple(_ p: SIMD3<Double>) -> String { "(\(real(p.x)),\(real(p.y)),\(real(p.z)))" }

    @discardableResult
    func add(_ body: String) -> Int {
        let id = next
        next += 1
        lines.append("#\(id)=\(body);")
        return id
    }

    func vertex(_ p: SIMD3<Double>) -> Int {
        let point = add("CARTESIAN_POINT('',\(Self.triple(p)))")
        let id = add("VERTEX_POINT('',#\(point))")
        vertexPoints[id] = p
        return id
    }

    func direction(_ d: SIMD3<Double>) -> Int { add("DIRECTION('',\(Self.triple(d)))") }

    func placement(origin: SIMD3<Double>, axis: SIMD3<Double>? = nil, ref: SIMD3<Double>? = nil) -> Int {
        let location = add("CARTESIAN_POINT('',\(Self.triple(origin)))")
        let axisRef = axis.map { "#\(direction($0))" } ?? "$"
        let refRef = ref.map { "#\(direction($0))" } ?? "$"
        return add("AXIS2_PLACEMENT_3D('',#\(location),\(axisRef),\(refRef))")
    }

    func lineEdge(_ a: Int, _ b: Int) -> Int {
        let p = vertexPoints[a]!
        let q = vertexPoints[b]!
        let vector = add("VECTOR('',#\(direction(simd_normalize(q - p))),1.0E+00)")
        let curve = add("LINE('',#\(add("CARTESIAN_POINT('',\(Self.triple(p)))")),#\(vector))")
        return add("EDGE_CURVE('',#\(a),#\(b),#\(curve),.T.)")
    }

    func circleEdge(center: SIMD3<Double>, radius: Double) -> (edge: Int, vertex: Int) {
        let start = vertex(center + SIMD3(radius, 0, 0))
        let circle = add("CIRCLE('',#\(placement(origin: center)),\(Self.real(radius)))")
        return (add("EDGE_CURVE('',#\(start),#\(start),#\(circle),.T.)"), start)
    }

    typealias Use = (edge: Int, forward: Bool)
    typealias Bound = (uses: [Use], forward: Bool)

    /// An ADVANCED_FACE; the first bound is the outer one.
    func face(_ bounds: [Bound], surface: Int, sameSense: Bool = true) -> Int {
        var boundIDs: [Int] = []
        for (index, bound) in bounds.enumerated() {
            let oriented = bound.uses.map { add("ORIENTED_EDGE('',*,*,#\($0.edge),.\($0.forward ? "T" : "F").)") }
            let loop = add("EDGE_LOOP('',(\(oriented.map { "#\($0)" }.joined(separator: ","))))")
            let type = index == 0 ? "FACE_OUTER_BOUND" : "FACE_BOUND"
            boundIDs.append(add("\(type)('',#\(loop),.\(bound.forward ? "T" : "F").)"))
        }
        return add("ADVANCED_FACE('',(\(boundIDs.map { "#\($0)" }.joined(separator: ","))),#\(surface),.\(sameSense ? "T" : "F").)")
    }

    func plane(origin: SIMD3<Double>, normal: SIMD3<Double>, ref: SIMD3<Double>) -> Int {
        add("PLANE('',#\(placement(origin: origin, axis: normal, ref: ref)))")
    }

    // MARK: Solids

    /// A box. With `hole`, a through hole along Z at the centre, whose wall is a seam-form
    /// cylinder face with `same_sense = .F` (its normal points into the hole).
    /// `unsupportedFace` swaps that face's surface for a B-spline surface.
    func box(min lo: SIMD3<Double>, size: SIMD3<Double>, hole radius: Double? = nil,
             unsupportedFace: Int? = nil) -> Int {
        let hi = lo + size
        let vertices = (0..<8).map { i in
            vertex(SIMD3(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z))
        }
        var edges: [[Int]: Int] = [:]
        for a in 0..<8 {
            for bit in 0..<3 where a & (1 << bit) == 0 {
                let b = a | (1 << bit)
                edges[[a, b]] = lineEdge(vertices[a], vertices[b])
            }
        }
        func use(_ from: Int, _ to: Int) -> Use { (edges[[min(from, to), max(from, to)]]!, from < to) }

        var holeEdges: (bottom: Int, top: Int, seam: Int)?
        if let radius {
            let center = lo + size / 2
            let bottom = circleEdge(center: SIMD3(center.x, center.y, lo.z), radius: radius)
            let top = circleEdge(center: SIMD3(center.x, center.y, hi.z), radius: radius)
            holeEdges = (bottom.edge, top.edge, lineEdge(bottom.vertex, top.vertex))
        }

        var faces: [Int] = []
        var faceNumber = 0
        for axis in 0..<3 {
            for side in 0..<2 {
                let others = (0..<3).filter { $0 != axis }
                func index(_ p: Int, _ q: Int) -> Int { side << axis | p << others[0] | q << others[1] }
                let cycle = [index(0, 0), index(1, 0), index(1, 1), index(0, 1)]
                var normal = SIMD3<Double>.zero
                normal[axis] = side == 1 ? 1 : -1
                var ref = SIMD3<Double>.zero
                ref[others[0]] = 1
                var origin = lo
                origin[axis] = side == 1 ? hi[axis] : lo[axis]

                var bounds: [Bound] = [((0..<4).map { use(cycle[$0], cycle[($0 + 1) % 4]) }, true)]
                if let holeEdges, axis == 2 {
                    bounds.append(([(side == 1 ? holeEdges.top : holeEdges.bottom, true)], true))
                }
                let surface: Int
                if faceNumber == unsupportedFace {
                    surface = add("B_SPLINE_SURFACE_WITH_KNOTS('',1,1,((#1,#1),(#1,#1)),"
                                  + ".UNSPECIFIED.,.F.,.F.,.F.,(2,2),(2,2),(0.,1.),(0.,1.),.UNSPECIFIED.)")
                } else {
                    surface = plane(origin: origin, normal: normal, ref: ref)
                }
                faces.append(face(bounds, surface: surface))
                faceNumber += 1
            }
        }
        if let radius, let holeEdges {
            let center = lo + size / 2
            let wall = add("CYLINDRICAL_SURFACE('',#\(placement(origin: SIMD3(center.x, center.y, lo.z))),\(Self.real(radius)))")
            let loop: [Use] = [(holeEdges.bottom, true), (holeEdges.seam, true), (holeEdges.top, false), (holeEdges.seam, false)]
            faces.append(face([(loop, true)], surface: wall, sameSense: false))
        }
        let shell = add("CLOSED_SHELL('',(\(faces.map { "#\($0)" }.joined(separator: ","))))")
        return add("MANIFOLD_SOLID_BREP('',#\(shell))")
    }

    /// A solid cylinder along Z. `seamless` puts both circles on the wall face as two bounds, the
    /// top one as a forward edge in a bound with orientation .F, and no seam edge.
    func cylinder(radius: Double, height: Double, seamless: Bool) -> Int {
        let bottom = circleEdge(center: .zero, radius: radius)
        let top = circleEdge(center: SIMD3(0, 0, height), radius: radius)
        var faces = [
            face([([(bottom.edge, true)], true)],
                 surface: plane(origin: .zero, normal: SIMD3(0, 0, -1), ref: SIMD3(1, 0, 0))),
            face([([(top.edge, true)], true)],
                 surface: plane(origin: SIMD3(0, 0, height), normal: SIMD3(0, 0, 1), ref: SIMD3(1, 0, 0)))
        ]
        let wall = add("CYLINDRICAL_SURFACE('',#\(placement(origin: .zero)),\(Self.real(radius)))")
        if seamless {
            faces.append(face([([(bottom.edge, true)], true), ([(top.edge, true)], false)], surface: wall))
        } else {
            let seam = lineEdge(bottom.vertex, top.vertex)
            let loop: [Use] = [(bottom.edge, true), (seam, true), (top.edge, false), (seam, false)]
            faces.append(face([(loop, true)], surface: wall))
        }
        let shell = add("CLOSED_SHELL('',(\(faces.map { "#\($0)" }.joined(separator: ","))))")
        return add("MANIFOLD_SOLID_BREP('',#\(shell))")
    }

    /// A single wall face between two circles, as an open shell model.
    func band(surface: Int, lower: (center: SIMD3<Double>, radius: Double), upper: (center: SIMD3<Double>, radius: Double)) -> Int {
        let bottom = circleEdge(center: lower.center, radius: lower.radius)
        let top = circleEdge(center: upper.center, radius: upper.radius)
        let wall = face([([(bottom.edge, true)], true), ([(top.edge, true)], false)], surface: surface)
        let shell = add("OPEN_SHELL('',(#\(wall)))")
        return add("SHELL_BASED_SURFACE_MODEL('',(#\(shell)))")
    }

    func data(items: [Int]) -> Data {
        let length = add("( LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.) )")
        let angle = add("( NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.) )")
        let context = add("( GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#\(length),#\(angle))) "
                          + "REPRESENTATION_CONTEXT('ctx','3D') )")
        add("ADVANCED_BREP_SHAPE_REPRESENTATION('',(\(items.map { "#\($0)" }.joined(separator: ","))),#\(context))")
        return Data(("ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('surface test'),'2;1');\nENDSEC;\nDATA;\n"
            + lines.joined(separator: "\n") + "\nENDSEC;\nEND-ISO-10303-21;\n").utf8)
    }
}

// MARK: - Helpers

private func corners(_ mesh: STEPBodyMesh, _ triangle: Int) -> [SIMD3<Double>] {
    (0..<3).map { SIMD3<Double>(mesh.positions[Int(mesh.indices[3 * triangle + $0])]) }
}

private func vertexNormals(_ mesh: STEPBodyMesh, _ triangle: Int) -> [SIMD3<Double>] {
    (0..<3).map { SIMD3<Double>(mesh.normals[Int(mesh.indices[3 * triangle + $0])]) }
}

private func area(_ mesh: STEPBodyMesh, _ triangles: Range<Int>) -> Double {
    triangles.reduce(0) { sum, n in
        let c = corners(mesh, n)
        return sum + 0.5 * simd_length(simd_cross(c[1] - c[0], c[2] - c[0]))
    }
}

private func geometricNormal(_ mesh: STEPBodyMesh, _ triangle: Int) -> SIMD3<Double> {
    let c = corners(mesh, triangle)
    return simd_normalize(simd_cross(c[1] - c[0], c[2] - c[0]))
}

private func centroid(_ mesh: STEPBodyMesh, _ triangle: Int) -> SIMD3<Double> {
    let c = corners(mesh, triangle)
    return (c[0] + c[1] + c[2]) / 3
}

/// Every triangle's winding agrees with every one of its stored normals.
private func windingAgreesWithNormals(_ mesh: STEPBodyMesh) -> Bool {
    (0..<mesh.triangleCount).allSatisfy { n in
        let g = geometricNormal(mesh, n)
        return vertexNormals(mesh, n).allSatisfy { simd_dot(g, $0) > 0.5 }
    }
}

private func polygon(_ points: [SIMD3<Double>]) -> (area: Double, perimeter: Double) {
    var area = 0.0
    var perimeter = 0.0
    for i in 0..<(points.count - 1) {
        let a = points[i]
        let b = points[i + 1]
        area += (a.x * b.y - b.x * a.y) / 2
        perimeter += simd_distance(a, b)
    }
    return (abs(area), perimeter)
}

private func geometry(_ builder: SolidBuilder, items: [Int]) throws -> STEPGeometry {
    try STEPEdgeImporter.parseGeometry(data: builder.data(items: items))
}

// MARK: - Face triangulation

@Suite("STEP surface tessellation")
struct STEPSurfaceTests {

    @Test func boxHasTwelveOutwardTrianglesRegisteredWithItsEdges() throws {
        let b = SolidBuilder()
        let solid = b.box(min: .zero, size: SIMD3(10, 10, 1))
        let imported = try geometry(b, items: [solid])
        let surfaces = imported.surfaces

        #expect(surfaces.diagnostics.isEmpty)
        #expect(surfaces.bodies.count == 1 && surfaces.unsurfacedBodies.isEmpty)
        #expect(surfaces.reachableFaceCount == 6 && surfaces.tessellatedFaceCount == 6 && surfaces.failedFaceCount == 0)
        #expect(surfaces.origin == SIMD3<Double>(0, 0, 1)) // min X, min Y, top: same as the edges
        let mesh = try #require(surfaces.bodies.first)
        #expect(mesh.triangleCount == 12 && surfaces.triangleCount == 12)
        #expect(mesh.faces.count == 6)
        #expect(mesh.faces.allSatisfy { $0.triangles.count == 2 && $0.sameSense })
        #expect(abs(area(mesh, 0..<12) - 220) < 1e-3)

        let center = SIMD3<Double>(5, 5, 0.5) - surfaces.origin
        for n in 0..<mesh.triangleCount {
            #expect(simd_dot(geometricNormal(mesh, n), centroid(mesh, n) - center) > 0, "triangle \(n) faces inward")
        }
        #expect(windingAgreesWithNormals(mesh))

        // The triangle range table finds the owning face, and only inside the mesh.
        for face in mesh.faces {
            for n in face.triangles { #expect(mesh.face(ofTriangle: n)?.faceID == face.faceID) }
        }
        #expect(mesh.face(ofTriangle: 12) == nil && mesh.face(ofTriangle: -1) == nil)
        #expect(Set(mesh.faces.map(\.faceID)).count == 6)

        // Same display origin as the wireframe: the corners line up exactly.
        let display = try STEPDisplayGeometry(model: imported.edges)
        #expect(display.origin == surfaces.origin)
        let meshMin = mesh.positions.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let edgeMin = display.bodies[0].points.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        #expect(meshMin == edgeMin)
    }

    @Test func plateWithThroughHoleCutsTheHoleAndTurnsItsWallInward() throws {
        let b = SolidBuilder()
        let solid = b.box(min: .zero, size: SIMD3(20, 20, 2), hole: 3)
        let imported = try geometry(b, items: [solid])
        let surfaces = imported.surfaces
        #expect(surfaces.diagnostics.isEmpty)
        let mesh = try #require(surfaces.bodies.first)
        #expect(mesh.faces.count == 7)

        // The hole is the wireframe's own circle polygon, so the areas are exact.
        let circle = try #require(imported.edges.edges.first { $0.kind == .circle })
        let (holeArea, holePerimeter) = polygon(circle.points)
        let expected = 2 * (400 - holeArea) + 4 * 40 + holePerimeter * 2
        #expect(abs(area(mesh, 0..<mesh.triangleCount) - expected) / expected < 1e-5)

        let wall = try #require(mesh.faces.first { if case .cylinder = $0.surface { return true } else { return false } })
        #expect(!wall.sameSense)
        let axis = SIMD3<Double>(10, 10, 0)
        for n in wall.triangles {
            for (position, normal) in zip(corners(mesh, n), vertexNormals(mesh, n)) {
                let radial = SIMD3<Double>(position.x + surfaces.origin.x - axis.x, position.y + surfaces.origin.y - axis.y, 0)
                #expect(simd_dot(normal, radial) < 0, "the hole wall must face the hole axis")
            }
        }
        #expect(windingAgreesWithNormals(mesh))

        // Top and bottom: no triangle may lie over the hole.
        for face in mesh.faces {
            guard case .plane = face.surface else { continue }
            for n in face.triangles {
                let c = centroid(mesh, n) + surfaces.origin
                if abs(c.z - 2) < 1e-6 || abs(c.z) < 1e-6 {
                    #expect(simd_distance(SIMD2(c.x, c.y), SIMD2(10, 10)) > 2.5, "triangle over the hole")
                }
            }
        }
    }

    @Test func solidCylinderWithSeamEdgeHasOutwardWall() throws {
        let b = SolidBuilder()
        let solid = b.cylinder(radius: 5, height: 10, seamless: false)
        let imported = try geometry(b, items: [solid])
        let mesh = try #require(imported.surfaces.bodies.first)
        #expect(imported.surfaces.diagnostics.isEmpty)
        let (capArea, perimeter) = polygon(try #require(imported.edges.edges.first { $0.kind == .circle }).points)
        let wall = try #require(mesh.faces.first { if case .cylinder = $0.surface { return true } else { return false } })
        #expect(abs(area(mesh, wall.triangles) - perimeter * 10) < 1e-3)
        let capTriangles = mesh.faces.filter { if case .plane = $0.surface { return true } else { return false } }
        for cap in capTriangles { #expect(abs(area(mesh, cap.triangles) - capArea) < 1e-3) }
        for n in wall.triangles {
            for (position, normal) in zip(corners(mesh, n), vertexNormals(mesh, n)) {
                let radial = SIMD3<Double>(position.x + imported.surfaces.origin.x, position.y + imported.surfaces.origin.y, 0)
                #expect(simd_dot(normal, radial) > 0)
            }
        }
        #expect(windingAgreesWithNormals(mesh))
    }

    @Test func seamlessCylinderWallBetweenTwoCirclesIsClosedAndOutward() throws {
        // Two wrapping loops and no seam edge; the top bound is reversed by its orientation flag.
        let b = SolidBuilder()
        let solid = b.cylinder(radius: 5, height: 10, seamless: true)
        let imported = try geometry(b, items: [solid])
        #expect(imported.surfaces.diagnostics.isEmpty)
        let mesh = try #require(imported.surfaces.bodies.first)
        let (_, perimeter) = polygon(try #require(imported.edges.edges.first { $0.kind == .circle }).points)
        let wall = try #require(mesh.faces.first { if case .cylinder = $0.surface { return true } else { return false } })
        #expect(abs(area(mesh, wall.triangles) - perimeter * 10) < 1e-3)
        #expect(windingAgreesWithNormals(mesh))
        for n in wall.triangles {
            let c = centroid(mesh, n) + imported.surfaces.origin
            #expect(simd_dot(geometricNormal(mesh, n), SIMD3(c.x, c.y, 0)) > 0)
        }
    }

    @Test func sphereBandPlacesInteriorPointsOnTheSphere() throws {
        let b = SolidBuilder()
        let sphere = b.add("SPHERICAL_SURFACE('',#\(b.placement(origin: .zero)),5.0E+00)")
        let band = b.band(surface: sphere, lower: (SIMD3(0, 0, -3), 4), upper: (SIMD3(0, 0, 3), 4))
        let imported = try geometry(b, items: [band])
        #expect(imported.surfaces.diagnostics.isEmpty)
        let mesh = try #require(imported.surfaces.bodies.first)
        let origin = imported.surfaces.origin
        // 2πRh = 2π·5·6, a little less for chords.
        let total = area(mesh, 0..<mesh.triangleCount)
        #expect(total < 2 * Double.pi * 5 * 6 && total > 2 * Double.pi * 5 * 6 * 0.99)
        for position in mesh.positions {
            let distance = simd_length(SIMD3<Double>(position) + origin)
            #expect(distance > 4.97 && distance < 5.0005, "point \(distance) is off the sphere")
        }
        // More than a single row of triangles between the two circles.
        #expect(Set(mesh.positions.map { ($0.z * 100).rounded() }).count > 6)
        for n in 0..<mesh.triangleCount {
            #expect(simd_dot(geometricNormal(mesh, n), centroid(mesh, n) + origin) > 0)
        }
        #expect(windingAgreesWithNormals(mesh))
    }

    @Test func coneFrustumLeansOutwardAndBackward() throws {
        let b = SolidBuilder()
        // Radius 5 at z = 0 growing by 1 mm per mm of height (45 degrees).
        let cone = b.add("CONICAL_SURFACE('',#\(b.placement(origin: .zero)),5.0E+00,\(SolidBuilder.real(Double.pi / 4)))")
        let band = b.band(surface: cone, lower: (.zero, 5), upper: (SIMD3(0, 0, 5), 10))
        let imported = try geometry(b, items: [band])
        #expect(imported.surfaces.diagnostics.isEmpty)
        let mesh = try #require(imported.surfaces.bodies.first)
        let expected = Double.pi * (5 + 10) * 50.0.squareRoot()
        let total = area(mesh, 0..<mesh.triangleCount)
        #expect(total < expected && total > expected * 0.99)
        for n in 0..<mesh.triangleCount {
            let g = geometricNormal(mesh, n)
            #expect(g.z < 0, "a cone that widens upward faces down")
            #expect(simd_dot(g, SIMD3(centroid(mesh, n).x + imported.surfaces.origin.x,
                                      centroid(mesh, n).y + imported.surfaces.origin.y, 0)) > 0)
        }
        #expect(windingAgreesWithNormals(mesh))
    }

    @Test func unsupportedFaceDropsTheBodySurfaceButKeepsItsEdges() throws {
        let b = SolidBuilder()
        let solid = b.box(min: .zero, size: SIMD3(10, 10, 1), unsupportedFace: 3)
        let imported = try geometry(b, items: [solid])
        #expect(imported.edges.edges.count == 12)
        let surfaces = imported.surfaces
        #expect(surfaces.bodies.isEmpty, "a partial occluder would misclassify visible edges as hidden")
        #expect(surfaces.unsurfacedBodies.count == 1)
        #expect(surfaces.reachableFaceCount == 6 && surfaces.failedFaceCount == 1 && surfaces.tessellatedFaceCount == 0)
        #expect(surfaces.diagnostics.contains { $0.message.contains("Unsupported surface type B_SPLINE_SURFACE_WITH_KNOTS") })
        #expect(surfaces.diagnostics.contains { $0.message.contains("No hidden-edge surface for body") })
    }

    @Test func missingBoundaryEdgeFailsTheFaceInsteadOfInventingAChord() throws {
        // An unsupported edge curve is skipped by the extractor, so the faces that use it cannot close.
        let b = SolidBuilder()
        let solid = b.box(min: .zero, size: SIMD3(10, 10, 1))
        var data = String(decoding: b.data(items: [solid]), as: UTF8.self)
        data = data.replacingOccurrences(of: "LINE('',", with: "PARABOLA('',", options: [], range: data.range(of: "LINE('',"))
        // The tolerant parse still succeeds; only edge extraction is affected.
        let imported = try STEPEdgeImporter.parseGeometry(data: Data(data.utf8))
        #expect(imported.edges.skippedEdgeCount >= 1)
        #expect(imported.surfaces.bodies.isEmpty && imported.surfaces.unsurfacedBodies.count == 1)
        #expect(imported.surfaces.diagnostics.contains { $0.message.contains("has no extracted geometry") })
    }

    @Test func severalBodiesAreTessellatedIndependently() throws {
        let b = SolidBuilder()
        let first = b.box(min: .zero, size: SIMD3(10, 10, 1))
        let second = b.box(min: SIMD3(30, 5, 0), size: SIMD3(4, 4, 4), hole: 1)
        let imported = try geometry(b, items: [first, second])
        let surfaces = imported.surfaces
        #expect(surfaces.diagnostics.isEmpty)
        #expect(surfaces.bodies.count == 2)
        #expect(Set(surfaces.bodies.map(\.id)).count == 2)
        #expect(surfaces.bodies.first { $0.id.entityID == first }?.triangleCount == 12)
        let withHole = try #require(surfaces.bodies.first { $0.id.entityID == second })
        #expect(withHole.faces.count == 7)
        // Every body's indices stay inside its own vertex arrays.
        for mesh in surfaces.bodies {
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
            #expect(mesh.positions.count == mesh.normals.count)
        }
        #expect(surfaces.origin == STEPDisplayGeometry.displayOrigin(bounds: imported.edges.bounds))
    }

    @Test func finerToleranceAddsTrianglesToCurvedFacesOnly() throws {
        func triangles(_ tolerance: Double) throws -> (plane: Int, wall: Int) {
            let b = SolidBuilder()
            let solid = b.cylinder(radius: 5, height: 10, seamless: false)
            let imported = try STEPEdgeImporter.parseGeometry(data: b.data(items: [solid]),
                                                              options: STEPImportOptions(chordToleranceMM: tolerance))
            let mesh = try #require(imported.surfaces.bodies.first)
            let wall = try #require(mesh.faces.first { if case .cylinder = $0.surface { return true } else { return false } })
            return (mesh.triangleCount - wall.triangles.count, wall.triangles.count)
        }
        let coarse = try triangles(0.5)
        let fine = try triangles(0.001)
        #expect(fine.wall > coarse.wall && fine.plane > coarse.plane, "caps follow the circle's own sampling")
    }

    @Test func cancellationAndBadToleranceAreNotPartialResults() async throws {
        let b = SolidBuilder()
        let data = b.data(items: [b.box(min: .zero, size: SIMD3(10, 10, 1))])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try STEPEdgeImporter.parseGeometry(data: data)
                Issue.record("A cancelled import should throw")
            } catch is CancellationError { }
        }
        await task.value
        #expect(throws: STEPParseError.self) {
            try STEPEdgeImporter.parseGeometry(data: data, options: STEPImportOptions(chordToleranceMM: 0))
        }
    }

    // MARK: Triangulator

    private func flat(_ u: Double, _ v: Double) -> STEPSlabTriangulator.Vertex {
        STEPSlabTriangulator.Vertex(u: u, v: v, position: SIMD3(u, v, 0))
    }

    private func loop(_ points: [(Double, Double)]) -> [STEPSlabTriangulator.Segment] {
        points.indices.map { i in
            STEPSlabTriangulator.Segment(a: flat(points[i].0, points[i].1),
                                         b: flat(points[(i + 1) % points.count].0, points[(i + 1) % points.count].1))
        }
    }

    private let planar = STEPSlabTriangulator.Sampling(evaluate: { SIMD3($0, $1, 0) }, rows: nil, latticeStep: nil)

    @Test func triangulatorHandlesConcaveShapesAndHoles() throws {
        let l = try STEPSlabTriangulator.triangulate(loop([(0, 0), (4, 0), (4, 2), (2, 2), (2, 4), (0, 4)]),
                                                      sampling: planar, triangleLimit: 100)
        func total(_ r: STEPSlabTriangulator.Result) -> Double {
            r.triangles.reduce(0) { sum, t in
                let a = r.vertices[t.x].position, b = r.vertices[t.y].position, c = r.vertices[t.z].position
                return sum + 0.5 * simd_length(simd_cross(b - a, c - a))
            }
        }
        #expect(abs(total(l) - 12) < 1e-12)
        let holed = try STEPSlabTriangulator.triangulate(
            loop([(0, 0), (10, 0), (10, 10), (0, 10)]) + loop([(4, 4), (4, 6), (6, 6), (6, 4)]),
            sampling: planar, triangleLimit: 100)
        #expect(abs(total(holed) - 96) < 1e-12)
        // Counter-clockwise in (u, v) means +Z for this flat surface.
        for t in holed.triangles {
            let a = holed.vertices[t.x].position, b = holed.vertices[t.y].position, c = holed.vertices[t.z].position
            #expect(simd_cross(b - a, c - a).z > 0)
        }
    }

    @Test func triangulatorRejectsOpenDegenerateAndOversizedInput() {
        // A triangle missing its last side: the slab right of x = 2 has one edge, not two.
        var open = loop([(0, 0), (4, 0), (2, 3)])
        open.remove(at: 1)
        #expect(throws: STEPParseError.self) {
            try STEPSlabTriangulator.triangulate(open, sampling: planar, triangleLimit: 100)
        }
        #expect(throws: STEPParseError.self) {
            try STEPSlabTriangulator.triangulate([], sampling: planar, triangleLimit: 100)
        }
        #expect(throws: STEPParseError.self) {
            try STEPSlabTriangulator.triangulate(loop([(1, 0), (1, 5), (1, 3)]), sampling: planar, triangleLimit: 100)
        }
        #expect(throws: STEPParseError.self) {
            try STEPSlabTriangulator.triangulate(loop([(0, 0), (4, 0), (4, 4), (0, 4)]), sampling: planar, triangleLimit: 1)
        }
        let nonfinite = [STEPSlabTriangulator.Segment(a: flat(0, 0), b: flat(.nan, 1))]
        #expect(throws: STEPParseError.self) {
            try STEPSlabTriangulator.triangulate(nonfinite, sampling: planar, triangleLimit: 100)
        }
    }

    // MARK: Scene

    @Test @MainActor func sceneAttachesOccludersAndSwitchesHiddenEdgeMode() throws {
        let b = SolidBuilder()
        let imported = try geometry(b, items: [b.box(min: .zero, size: SIMD3(10, 10, 1))])
        let content = try STEPViewerContent(model: imported.edges,
                                            geometry: STEPDisplayGeometry(model: imported.edges),
                                            surfaces: imported.surfaces)
        let scene = STEPDocumentScene(content: content)
        #expect(scene.hasSurfaces && scene.hiddenEdgeMode == .dotted)
        var object = try #require(scene.baseObjects.first)
        #expect(object.occluderFaces.count == 36)
        #expect(object.hiddenLineStyle == .dotted)
        let edgeMin = object.points.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let faceMin = object.occluderFaces.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        #expect(edgeMin == faceMin, "occluders and edges must be registered")

        scene.hiddenEdgeMode = .hidden
        object = try #require(scene.baseObjects.first)
        #expect(object.hiddenLineStyle == .omitted && object.occluderFaces.count == 36)

        scene.hiddenEdgeMode = .solid
        object = try #require(scene.baseObjects.first)
        #expect(object.hiddenLineStyle == .roleDefault && object.occluderFaces.isEmpty)

        // The offset moves edges and faces together.
        scene.hiddenEdgeMode = .dotted
        scene.setOffset(SIMD3(100, 20, -3))
        object = try #require(scene.baseObjects.first)
        let movedEdges = object.points.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let movedFaces = object.occluderFaces.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        #expect(movedEdges == SIMD3<Float>(100, 20, -4) && movedFaces == movedEdges)

        // Selecting and clearing edges never rebuilds the base objects.
        let baseIDs = scene.baseObjects.map(\.id)
        scene.select(content.model.edges[0].id, extend: false)
        scene.clearSelection()
        #expect(scene.baseObjects.map(\.id) == baseIDs)
    }

    @Test @MainActor func sceneWithoutSurfacesDrawsSolidEdgesAsToday() throws {
        let b = SolidBuilder()
        let imported = try geometry(b, items: [b.box(min: .zero, size: SIMD3(10, 10, 1), unsupportedFace: 0)])
        let content = try STEPViewerContent(model: imported.edges,
                                            geometry: STEPDisplayGeometry(model: imported.edges),
                                            surfaces: imported.surfaces)
        let scene = STEPDocumentScene(content: content)
        #expect(!scene.hasSurfaces && scene.hiddenEdgeMode == .solid)
        scene.hiddenEdgeMode = .dotted
        let object = try #require(scene.baseObjects.first)
        #expect(object.occluderFaces.isEmpty && object.hiddenLineStyle == .roleDefault)

        // A viewer content built the old way (no surfaces) behaves the same.
        let legacy = try STEPViewerContent(model: imported.edges, geometry: STEPDisplayGeometry(model: imported.edges))
        #expect(STEPDocumentScene(content: legacy).baseObjects.first?.occluderFaces.isEmpty == true)
    }
}
