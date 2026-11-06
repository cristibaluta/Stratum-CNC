import Foundation
import simd

// MARK: - Output

/// The triangles of one face inside its body's mesh.
struct STEPFaceMesh: Sendable {
    /// ADVANCED_FACE / FACE_SURFACE entity ID.
    let faceID: Int
    /// Exact surface data for later picking and feature recognition.
    let surface: STEPSurface
    /// The face's own `same_sense` flag (not the shell orientation).
    let sameSense: Bool
    /// Triangle numbers (index `3 * n ..< 3 * n + 3` in `indices`) that belong to this face.
    let triangles: Range<Int>
}

/// One body's triangle mesh. Positions are Float, millimetres relative to the display origin
/// (the same origin as `STEPDisplayGeometry`), so they line up with the wireframe points.
/// Normals follow the face (analytic, never averaged across a sharp edge) and point out of
/// the material. The winding of every triangle agrees with its normal.
struct STEPBodyMesh: Sendable {
    let id: STEPBodyID
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    /// Sorted by triangle range, so a triangle number finds its face by binary search.
    var faces: [STEPFaceMesh] = []

    var triangleCount: Int { indices.count / 3 }

    /// The face a triangle belongs to (step 7 will pick through this).
    func face(ofTriangle triangle: Int) -> STEPFaceMesh? {
        var low = 0
        var high = faces.count
        while low < high {
            let middle = (low + high) / 2
            if faces[middle].triangles.upperBound <= triangle { low = middle + 1 } else { high = middle }
        }
        guard low < faces.count, faces[low].triangles.contains(triangle) else { return nil }
        return faces[low]
    }

    /// Three points per triangle moved by `offset`: the layout of `RenderObject.occluderFaces`.
    func occluderTriangles(offset: SIMD3<Float> = .zero) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(indices.count)
        for index in indices { result.append(positions[Int(index)] + offset) }
        return result
    }
}

struct STEPSurfaceModel: Sendable {
    /// Display origin the Float positions are relative to.
    var origin: SIMD3<Double> = .zero
    /// Bodies whose every face was tessellated. Only these may occlude edges.
    var bodies: [STEPBodyMesh] = []
    /// Bodies that had at least one unsupported or failed face. A partial occluder would
    /// misclassify visible edges as hidden, so such a body gets no surface at all.
    var unsurfacedBodies: [STEPBodyID] = []
    var diagnostics: [STEPDiagnostic] = []
    /// Distinct faces reachable from the supported bodies.
    var reachableFaceCount = 0
    /// Faces that could not be tessellated (each has a diagnostic).
    var failedFaceCount = 0
    /// Faces inside `bodies`.
    var tessellatedFaceCount = 0
    var triangleCount: Int { bodies.reduce(0) { $0 + $1.triangleCount } }

    func mesh(for id: STEPBodyID) -> STEPBodyMesh? { bodies.first { $0.id == id } }
}

// MARK: - Tessellator

/// Turns the faces of each body into triangles, reusing the wireframe's sampled edges as
/// face boundaries so faces and edges agree exactly.
///
/// Supported: planes (outer loop with holes) and cylinders, cones, spheres and tori trimmed
/// by their loops, including faces that wrap the whole axis (a cylinder between two
/// circles) and the seam-edge form of the same. Not yet: B-spline and swept surfaces, faces
/// that reach a sphere's pole or a cone's apex, vertex or polyline loops, oriented faces.
/// Any such face drops the whole body's surface, with a diagnostic.
///
/// Task-confined like `STEPFile`; use through `STEPEdgeImporter.parseGeometry`.
final class STEPTessellator {
    /// Cap for the whole import. The renderer keeps a CPU and a GPU copy of every triangle,
    /// roughly 150 bytes each, so this bounds the extra memory to a few hundred MB.
    static let maximumTriangles = 1_000_000

    private let file: STEPFile
    private let model: STEPEdgeModel
    private let tolerance: Double
    private var surfaces: STEPSurfaceModel
    private var triangleBudget = STEPTessellator.maximumTriangles

    private static let bodyTypes: Set<String> = ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"]
    private static let surfaceTypes: Set<String> = ["PLANE", "CYLINDRICAL_SURFACE", "CONICAL_SURFACE",
                                                    "SPHERICAL_SURFACE", "TOROIDAL_SURFACE"]
    /// Two boundary edges meet when their end points are this close (mm).
    private static let connectionTolerance = 1e-6

    init(file: STEPFile, model: STEPEdgeModel, options: STEPImportOptions) {
        self.file = file
        self.model = model
        tolerance = options.chordToleranceMM
        surfaces = STEPSurfaceModel(origin: STEPDisplayGeometry.displayOrigin(bounds: model.bounds))
    }

    func tessellate() throws -> STEPSurfaceModel {
        try Task.checkCancellation()
        guard tolerance.isFinite, tolerance > 0 else {
            throw STEPParseError("Chord tolerance must be finite and positive")
        }
        let edgesByBody = Dictionary(grouping: model.edges, by: { $0.id.bodyID })
        for body in model.bodies {
            try Task.checkCancellation()
            try tessellate(body: body, edges: edgesByBody[body.id] ?? [])
        }
        return surfaces
    }

    private func diagnose(_ id: Int?, _ message: String) {
        surfaces.diagnostics.append(STEPDiagnostic(entityID: id, message: message))
    }

    // MARK: Bodies

    private func tessellate(body: STEPBodyInfo, edges: [STEPEdge]) throws {
        let faces: [(id: Int, flipped: Bool)]
        do {
            faces = try collectFaces(bodyID: body.id.entityID)
        } catch let error as STEPParseError {
            surfaces.unsurfacedBodies.append(body.id)
            diagnose(body.id.entityID, "No surface for body #\(body.id.entityID): \(error.description)")
            return
        }
        surfaces.reachableFaceCount += faces.count
        let edgeByID = Dictionary(edges.map { ($0.id.entityID, $0) }, uniquingKeysWith: { first, _ in first })
        let contextID = body.contextID
        let scale = body.unitScaleToMM
        var mesh = STEPBodyMesh(id: body.id)
        var surfaceCache: [Int: STEPSurface] = [:]
        var failed = 0

        for face in faces {
            try Task.checkCancellation()
            do {
                let parsed = try parseFace(face.id)
                let surface: STEPSurface
                if let cached = surfaceCache[parsed.surfaceID] {
                    surface = cached
                } else {
                    surface = try parseSurface(parsed.surfaceID, scale: scale, contextID: contextID)
                    surfaceCache[parsed.surfaceID] = surface
                }
                // The body is dropped once a face fails; later faces are only classified.
                if failed > 0 { continue }
                try tessellateFace(face.id, parsed: parsed, surface: surface, shellFlipped: face.flipped,
                                   edges: edgeByID, into: &mesh)
            } catch let error as STEPParseError {
                failed += 1
                diagnose(face.id, "Face not tessellated: \(error.description)")
            }
        }

        if failed > 0 {
            surfaces.failedFaceCount += failed
            surfaces.unsurfacedBodies.append(body.id)
            triangleBudget += mesh.triangleCount
            diagnose(body.id.entityID,
                     "No hidden-edge surface for body #\(body.id.entityID): \(failed) of \(faces.count) faces could not be tessellated")
        } else if mesh.triangleCount > 0 {
            surfaces.tessellatedFaceCount += faces.count
            surfaces.bodies.append(mesh)
        }
    }

    /// Faces of the body's shells, each with whether its shell is reversed (the void shells of
    /// a BREP_WITH_VOIDS are ORIENTED_CLOSED_SHELL with orientation .F). Sorted by face ID.
    private func collectFaces(bodyID: Int) throws -> [(id: Int, flipped: Bool)] {
        var faces: [Int: Bool] = [:]

        func addShell(_ id: Int, flipped: Bool, depth: Int) throws {
            try Task.checkCancellation()
            guard depth < 8 else { throw STEPParseError("Shell nesting is too deep at #\(id)") }
            let components = try file.components(id)
            if let oriented = components.first(where: { $0.type == "ORIENTED_CLOSED_SHELL" }) {
                guard let orientation = try oriented.parameters.argument(3).enumeration,
                      orientation == "T" || orientation == "F" else {
                    throw STEPParseError("Invalid ORIENTED_CLOSED_SHELL orientation at #\(id)")
                }
                try addShell(try oriented.parameters.reference(at: 2),
                             flipped: flipped != (orientation == "F"), depth: depth + 1)
                return
            }
            guard let shell = components.first(where: { $0.type == "CLOSED_SHELL" || $0.type == "OPEN_SHELL" }) else {
                throw STEPParseError("Unsupported shell at #\(id)")
            }
            for face in try shell.parameters.references(at: 1) {
                guard file.hasType(face, "ADVANCED_FACE") || file.hasType(face, "FACE_SURFACE") else {
                    throw STEPParseError("Unsupported face type at #\(face)")
                }
                if faces[face] == nil { faces[face] = flipped }
            }
        }

        let components = try file.components(bodyID)
        guard let body = components.first(where: { Self.bodyTypes.contains($0.type) }) else {
            throw STEPParseError("Unsupported body at #\(bodyID)")
        }
        let p = body.parameters
        switch body.type {
            case "MANIFOLD_SOLID_BREP":
                try addShell(try p.reference(at: 1), flipped: false, depth: 0)
            case "BREP_WITH_VOIDS":
                try addShell(try p.reference(at: 1), flipped: false, depth: 0)
                for void in try p.references(at: 2) { try addShell(void, flipped: false, depth: 0) }
            default:
                for shell in try p.references(at: 1) { try addShell(shell, flipped: false, depth: 0) }
        }
        return faces.keys.sorted().map { (id: $0, flipped: faces[$0] ?? false) }
    }

    // MARK: Faces and surfaces

    private struct ParsedFace {
        let boundIDs: [Int]
        let surfaceID: Int
        let sameSense: Bool
    }

    private func parseFace(_ id: Int) throws -> ParsedFace {
        let components = try file.components(id)
        guard let part = components.first(where: { $0.type == "ADVANCED_FACE" || $0.type == "FACE_SURFACE" }) else {
            throw STEPParseError("Unsupported face type")
        }
        let p = part.parameters
        guard let sense = try p.argument(3).enumeration, sense == "T" || sense == "F" else {
            throw STEPParseError("Invalid face same_sense")
        }
        return ParsedFace(boundIDs: try p.references(at: 1), surfaceID: try p.reference(at: 2), sameSense: sense == "T")
    }

    private func parseSurface(_ id: Int, scale: Double, contextID: Int) throws -> STEPSurface {
        let components = try file.components(id)
        guard let part = components.first(where: { Self.surfaceTypes.contains($0.type) }) else {
            throw STEPParseError("Unsupported surface type \(components.first?.type ?? "unknown") at #\(id)")
        }
        let p = part.parameters
        // Only the frame helper is used: the resolver scales the placement's origin.
        let resolver = STEPCurveResolver(file: file, scaleToMM: scale, chordTolerance: tolerance,
                                         angleScaleToRadians: { 1 })
        let frame = try resolver.frame(try p.reference(at: 1))

        func length(_ index: Int, allowZero: Bool = false) throws -> Double {
            guard let value = try p.argument(index).number, value.isFinite,
                  allowZero ? value >= 0 : value > 0, (value * scale).isFinite else {
                throw STEPParseError("Invalid \(part.type) dimension at #\(id)")
            }
            return value * scale
        }

        switch part.type {
            case "PLANE":
                return .plane(frame)
            case "CYLINDRICAL_SURFACE":
                return .cylinder(frame, radius: try length(2))
            case "CONICAL_SURFACE":
                let radius = try length(2, allowZero: true)
                guard let angle = try p.argument(3).number, angle.isFinite else {
                    throw STEPParseError("Invalid CONICAL_SURFACE semi-angle at #\(id)")
                }
                let radiansPerUnit = try STEPUnits(file: file).angleScaleToRadians(contextID: contextID)
                let halfAngle = angle * radiansPerUnit
                guard halfAngle.isFinite, abs(halfAngle) < Double.pi / 2 - 1e-6 else {
                    throw STEPParseError("Invalid CONICAL_SURFACE semi-angle at #\(id)")
                }
                return .cone(frame, radius: radius, halfAngle: halfAngle)
            case "SPHERICAL_SURFACE":
                return .sphere(frame, radius: try length(2))
            default:
                let major = try length(2)
                let minor = try length(3)
                guard major > minor else { throw STEPParseError("Self-intersecting torus at #\(id) is not supported") }
                return .torus(frame, major: major, minor: minor)
        }
    }

    // MARK: Boundary loops

    /// The loop's sampled points in the face bound's direction, built from the wireframe's own
    /// edge polylines. Closed, without a repeated end point.
    private func loopPoints(bound id: Int, edges: [Int: STEPEdge]) throws -> [SIMD3<Double>] {
        let components = try file.components(id)
        guard let bound = components.first(where: { $0.type == "FACE_BOUND" || $0.type == "FACE_OUTER_BOUND" }) else {
            throw STEPParseError("Unsupported face bound #\(id)")
        }
        let loopID = try bound.parameters.reference(at: 1)
        guard let boundOrientation = try bound.parameters.argument(2).enumeration,
              boundOrientation == "T" || boundOrientation == "F" else {
            throw STEPParseError("Invalid face bound orientation at #\(id)")
        }
        guard file.hasType(loopID, "EDGE_LOOP") else {
            throw STEPParseError("Unsupported loop type at #\(loopID)")
        }
        var points: [SIMD3<Double>] = []
        for use in try file.parameters(loopID, type: "EDGE_LOOP").references(at: 1) {
            try Task.checkCancellation()
            let oriented = try file.parameters(use, type: "ORIENTED_EDGE")
            let edgeID = try oriented.reference(at: 3)
            guard let orientation = try oriented.argument(4).enumeration, orientation == "T" || orientation == "F" else {
                throw STEPParseError("Invalid ORIENTED_EDGE orientation at #\(use)")
            }
            guard let edge = edges[edgeID] else {
                throw STEPParseError("Boundary edge #\(edgeID) has no extracted geometry")
            }
            let piece = orientation == "T" ? edge.points : Array(edge.points.reversed())
            guard let first = piece.first else { continue }
            if let last = points.last {
                guard simd_distance(last, first) <= Self.connectionTolerance else {
                    throw STEPParseError("Face loop is not connected at edge #\(edgeID)")
                }
                for point in piece.dropFirst() {
                    if simd_distance(point, points[points.count - 1]) > 1e-12 { points.append(point) }
                }
            } else {
                points = piece
            }
        }
        guard points.count >= 2, simd_distance(points[0], points[points.count - 1]) <= Self.connectionTolerance else {
            throw STEPParseError("Face loop is not closed")
        }
        points.removeLast()
        guard points.count >= 3 else { throw STEPParseError("Face loop is degenerate") }
        // A bound with orientation .F runs against its loop.
        return boundOrientation == "T" ? points : points.reversed()
    }

    /// A boundary loop in the surface's (u, v) plane.
    private struct ParamLoop {
        typealias Vertex = STEPSlabTriangulator.Vertex
        typealias Segment = STEPSlabTriangulator.Segment

        var vertices: [Vertex]
        /// The first vertex again, moved by the loop's winding: where the last vertex connects.
        var closing: Vertex
        /// Whole turns the loop makes round the surface's axis (u) or tube (v).
        var windingU: Int
        var windingV: Int

        var uRange: ClosedRange<Double> { range(\.u) }
        var vRange: ClosedRange<Double> { range(\.v) }

        private func range(_ key: KeyPath<Vertex, Double>) -> ClosedRange<Double> {
            var low = closing[keyPath: key]
            var high = low
            for vertex in vertices {
                low = min(low, vertex[keyPath: key])
                high = max(high, vertex[keyPath: key])
            }
            return low...high
        }

        var segments: [Segment] {
            var result: [Segment] = []
            result.reserveCapacity(vertices.count)
            for i in vertices.indices {
                result.append(Segment(a: vertices[i], b: i + 1 < vertices.count ? vertices[i + 1] : closing))
            }
            return result
        }

        func shifted(du: Double, dv: Double) -> ParamLoop {
            var copy = self
            for i in copy.vertices.indices {
                copy.vertices[i].u += du
                copy.vertices[i].v += dv
            }
            copy.closing.u += du
            copy.closing.v += dv
            return copy
        }
    }

    /// Unwraps the loop's angles so neighbouring points stay within half a turn, and counts how
    /// many turns it makes.
    private func parametrize(_ points: [SIMD3<Double>], on surface: STEPSurface) throws -> ParamLoop {
        let raw = points.map { surface.parameters(of: $0) }
        if raw.contains(where: { $0.isPole }) {
            throw STEPParseError("Face reaches a pole or apex of its \(surface.kindName); not supported yet")
        }
        let twoPi = STEPAngle.twoPi
        var u = raw.map { $0.u }
        var v = raw.map { $0.v }
        for i in 1..<raw.count {
            if surface.isPeriodicU { u[i] += twoPi * ((u[i - 1] - u[i]) / twoPi).rounded() }
            if surface.isPeriodicV { v[i] += twoPi * ((v[i - 1] - v[i]) / twoPi).rounded() }
        }
        var closingU = u[0]
        var closingV = v[0]
        if surface.isPeriodicU { closingU += twoPi * ((u[u.count - 1] - u[0]) / twoPi).rounded() }
        if surface.isPeriodicV { closingV += twoPi * ((v[v.count - 1] - v[0]) / twoPi).rounded() }
        guard (u + v + [closingU, closingV]).allSatisfy({ $0.isFinite }) else {
            throw STEPParseError("Face loop has nonfinite parameters")
        }
        var vertices: [STEPSlabTriangulator.Vertex] = []
        vertices.reserveCapacity(points.count)
        for i in points.indices {
            vertices.append(STEPSlabTriangulator.Vertex(u: u[i], v: v[i], position: points[i]))
        }
        return ParamLoop(vertices: vertices,
                         closing: STEPSlabTriangulator.Vertex(u: closingU, v: closingV, position: points[0]),
                         windingU: Int(((closingU - u[0]) / twoPi).rounded()),
                         windingV: Int(((closingV - v[0]) / twoPi).rounded()))
    }

    // MARK: Face geometry

    private func tessellateFace(_ id: Int, parsed: ParsedFace, surface: STEPSurface, shellFlipped: Bool,
                                edges: [Int: STEPEdge], into mesh: inout STEPBodyMesh) throws {
        guard !parsed.boundIDs.isEmpty else { throw STEPParseError("Face has no boundary") }
        var loops: [ParamLoop] = []
        for bound in parsed.boundIDs {
            loops.append(try parametrize(try loopPoints(bound: bound, edges: edges), on: surface))
        }
        let segments = try boundarySegments(loops, surface: surface)
        let vValues = segments.flatMap { [$0.a.v, $0.b.v] }
        guard let vLow = vValues.min(), let vHigh = vValues.max() else { throw STEPParseError("Face has no boundary") }

        let result = try STEPSlabTriangulator.triangulate(segments,
                                                          sampling: sampling(for: surface, vRange: vLow...vHigh),
                                                          triangleLimit: triangleBudget)
        triangleBudget -= result.triangles.count

        // The surface normal is a face's front unless same_sense is false; a reversed shell
        // (a void) turns every face the other way again.
        let flip = (!parsed.sameSense) != shellFlipped
        let base = mesh.positions.count
        let origin = surfaces.origin
        mesh.positions.reserveCapacity(base + result.vertices.count)
        mesh.normals.reserveCapacity(base + result.vertices.count)
        for vertex in result.vertices {
            mesh.positions.append(SIMD3<Float>(vertex.position - origin))
            let normal = surface.normal(u: vertex.u, v: vertex.v)
            mesh.normals.append(SIMD3<Float>(flip ? -normal : normal))
        }
        let firstTriangle = mesh.indices.count / 3
        for triangle in result.triangles {
            let a = UInt32(base + triangle.x)
            let b = UInt32(base + triangle.y)
            let c = UInt32(base + triangle.z)
            if flip {
                mesh.indices.append(contentsOf: [a, c, b])
            } else {
                mesh.indices.append(contentsOf: [a, b, c])
            }
        }
        mesh.faces.append(STEPFaceMesh(faceID: id, surface: surface, sameSense: parsed.sameSense,
                                       triangles: firstTriangle..<(firstTriangle + result.triangles.count)))
    }

    /// The face's region as plain segments in (u, v): every closed loop as it is, or, for a face
    /// that goes all the way round its axis, the two wrapping loops cut to one period.
    private func boundarySegments(_ loops: [ParamLoop], surface: STEPSurface) throws -> [STEPSlabTriangulator.Segment] {
        guard loops.allSatisfy({ $0.windingV == 0 }) else {
            throw STEPParseError("Face wraps round the \(surface.kindName)'s tube; not supported yet")
        }
        let wrapping = loops.filter { $0.windingU != 0 }
        let plain = loops.filter { $0.windingU == 0 }

        if wrapping.isEmpty {
            // Closed polygons. For a periodic surface, bring every loop into the outermost
            // loop's turn; a loop that then falls outside it straddles the seam.
            guard let reference = plain.indices.max(by: { Self.area(plain[$0]) < Self.area(plain[$1]) }) else {
                throw STEPParseError("Face has no boundary")
            }
            var segments: [STEPSlabTriangulator.Segment] = []
            for (index, loop) in plain.enumerated() {
                if index == reference {
                    segments.append(contentsOf: loop.segments)
                } else {
                    let aligned = try align(loop, surface: surface,
                                            referenceU: plain[reference].uRange, referenceV: plain[reference].vRange)
                    segments.append(contentsOf: aligned.segments)
                }
            }
            return segments
        }

        // Two loops that each go once round, in opposite directions: a band such as a
        // cylinder between two circles with no seam edge. Both are cut to one period.
        guard wrapping.count == 2, wrapping[0].windingU + wrapping[1].windingU == 0,
              abs(wrapping[0].windingU) == 1 else {
            throw STEPParseError("Face wraps round the \(surface.kindName)'s axis in a way that is not supported yet")
        }
        let twoPi = STEPAngle.twoPi
        let start = wrapping[0].vertices[0].u
        let window = start...(start + twoPi)
        let vLow = min(wrapping[0].vRange.lowerBound, wrapping[1].vRange.lowerBound)
        let vHigh = max(wrapping[0].vRange.upperBound, wrapping[1].vRange.upperBound)
        var segments: [STEPSlabTriangulator.Segment] = []
        for loop in wrapping { segments.append(contentsOf: Self.cut(loop, to: window)) }
        for loop in plain {
            segments.append(contentsOf: try align(loop, surface: surface, referenceU: window, referenceV: vLow...vHigh).segments)
        }
        return segments
    }

    private static func area(_ loop: ParamLoop) -> Double {
        let u = loop.uRange
        let v = loop.vRange
        return (u.upperBound - u.lowerBound) * (v.upperBound - v.lowerBound)
    }

    /// Moves a closed loop by whole turns into the reference's range and checks it fits.
    private func align(_ loop: ParamLoop, surface: STEPSurface, referenceU: ClosedRange<Double>,
                       referenceV: ClosedRange<Double>) throws -> ParamLoop {
        let twoPi = STEPAngle.twoPi
        func mid(_ range: ClosedRange<Double>) -> Double { (range.lowerBound + range.upperBound) / 2 }
        var du = 0.0
        var dv = 0.0
        if surface.isPeriodicU { du = twoPi * ((mid(referenceU) - mid(loop.uRange)) / twoPi).rounded() }
        if surface.isPeriodicV { dv = twoPi * ((mid(referenceV) - mid(loop.vRange)) / twoPi).rounded() }
        let moved = loop.shifted(du: du, dv: dv)
        let slack = 1e-6
        if surface.isPeriodicU,
           moved.uRange.lowerBound < referenceU.lowerBound - slack || moved.uRange.upperBound > referenceU.upperBound + slack {
            throw STEPParseError("Face loop straddles the periodic seam of its \(surface.kindName)")
        }
        if surface.isPeriodicV,
           moved.vRange.lowerBound < referenceV.lowerBound - slack || moved.vRange.upperBound > referenceV.upperBound + slack {
            throw STEPParseError("Face loop straddles the periodic seam of its \(surface.kindName)")
        }
        return moved
    }

    /// One period of a wrapping loop: the loop and its copies one turn up or down, each
    /// segment clipped to the window. Every vertical line crosses the loop once.
    private static func cut(_ loop: ParamLoop, to window: ClosedRange<Double>) -> [STEPSlabTriangulator.Segment] {
        let twoPi = STEPAngle.twoPi
        let range = loop.uRange
        let first = Int(((window.lowerBound - range.upperBound) / twoPi).rounded(.up))
        let last = Int(((window.upperBound - range.lowerBound) / twoPi).rounded(.down))
        guard first <= last else { return [] }
        let base = loop.segments
        var result: [STEPSlabTriangulator.Segment] = []
        for k in first...last {
            let shift = Double(k) * twoPi
            for segment in base {
                var a = segment.a
                var b = segment.b
                a.u += shift
                b.u += shift
                let low = min(a.u, b.u)
                let high = max(a.u, b.u)
                guard high > window.lowerBound, low < window.upperBound, high > low else { continue }
                let from = max(low, window.lowerBound)
                let to = min(high, window.upperBound)
                func vertex(at u: Double) -> STEPSlabTriangulator.Vertex {
                    if u == a.u { return a }
                    if u == b.u { return b }
                    let t = (u - a.u) / (b.u - a.u)
                    return STEPSlabTriangulator.Vertex(u: u, v: a.v + (b.v - a.v) * t,
                                                       position: a.position + (b.position - a.position) * t)
                }
                result.append(STEPSlabTriangulator.Segment(a: vertex(at: from), b: vertex(at: to)))
            }
        }
        return result
    }

    // MARK: Resolution

    /// Largest angle between neighbouring samples on a circle of `radius` so the chord's
    /// sagitta stays within `tolerance`; the same rule the wireframe's circles use.
    private static func angularStep(radius: Double, tolerance: Double) -> Double {
        let ratio = min(2, tolerance / radius)
        let toleranceStep = 4 * asin(min(1, (ratio / 2).squareRoot()))
        return max(min(toleranceStep, STEPArcSampler.maximumAngularStep),
                   STEPAngle.twoPi / Double(STEPArcSampler.maximumSegments))
    }

    private func sampling(for surface: STEPSurface, vRange: ClosedRange<Double>) -> STEPSlabTriangulator.Sampling {
        var lattice: Double?
        if let radius = surface.widestRadius(vRange: vRange), radius > 0 {
            lattice = Self.angularStep(radius: radius, tolerance: tolerance)
        }
        var rows: ((Double, Double, Double) -> Int)?
        if let radius = surface.radiusAlongV, radius > 0 {
            let step = Self.angularStep(radius: radius, tolerance: tolerance)
            rows = { _, low, high in Int((abs(high - low) / step).rounded(.up)) }
        }
        return STEPSlabTriangulator.Sampling(evaluate: { u, v in surface.point(u: u, v: v) },
                                             rows: rows, latticeStep: lattice)
    }
}
