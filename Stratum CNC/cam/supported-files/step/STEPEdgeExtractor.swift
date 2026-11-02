import Foundation

/// Task-confined extraction state; no UI, renderer or 2D path dependencies.
final class STEPEdgeExtractor {
    private let file: STEPFile
    private let options: STEPImportOptions
    private var model: STEPEdgeModel
    private static let representationTypes: Set<String> = [
        "SHAPE_REPRESENTATION",
        "ADVANCED_BREP_SHAPE_REPRESENTATION",
        "MANIFOLD_SURFACE_SHAPE_REPRESENTATION",
        "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION"
    ]
    private static let bodyTypes: Set<String> = ["MANIFOLD_SOLID_BREP",
                                                 "BREP_WITH_VOIDS",
                                                 "SHELL_BASED_SURFACE_MODEL"]

    init(file: STEPFile, importID: UUID, options: STEPImportOptions) {
        self.file = file
        self.options = options
        model = STEPEdgeModel(importID: importID)
    }

    func extract() throws -> STEPEdgeModel {
        try Task.checkCancellation()
        if let scale = options.assumedUnitScaleToMM, !scale.isFinite || scale <= 0 {
            throw STEPParseError("Assumed unit scale must be finite and positive")
        }
        guard options.chordToleranceMM.isFinite, options.chordToleranceMM > 0 else {
            throw STEPParseError("Chord tolerance must be finite and positive")
        }
        let assemblies = file.entities(ofTypes: ["MAPPED_ITEM",
                                                 "NEXT_ASSEMBLY_USAGE_OCCURRENCE",
                                                 "REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION"])
        guard assemblies.isEmpty else {
            throw STEPParseError("Assembly placement is not supported yet (entity #\(assemblies[0]))")
        }
        model.indexedEntityCount = file.index.count

        for representationID in file.entities(ofTypes: Self.representationTypes) {
            try Task.checkCancellation()
            let parts = try file.components(representationID)

            guard let representation = parts.first(where: { $0.type == "REPRESENTATION" })
                ?? parts.first(where: { Self.representationTypes.contains($0.type) }) else {
                continue
            }
            let items = try representation.parameters.references(at: 1)
            let bodyIDs = Set(items.filter { id in Self.bodyTypes.contains { file.hasType(id, $0) } }).sorted()

            guard !bodyIDs.isEmpty else {
                continue
            }
            let contextID = try representation.parameters.reference(at: 2)
            let scale: Double
            let assumed: Bool
            do {
                scale = try STEPUnits(file: file).scaleToMM(contextID: contextID)
                assumed = false
            } catch let error as STEPParseError {
                guard let fallback = options.assumedUnitScaleToMM else {
                    throw error
                }
                scale = fallback
                assumed = true
                diagnose(contextID, "\(error); explicitly assuming \(fallback) mm per source unit")
            }
            let resolver = STEPCurveResolver(file: file, scaleToMM: scale, chordTolerance: options.chordToleranceMM,
                                             angleScaleToRadians: { try self.angleScale(context: contextID) })
            for bodyID in bodyIDs {
                let identity = STEPBodyID(representationID: representationID, entityID: bodyID)
                model.bodies.append(STEPBodyInfo(id: identity, contextID: contextID, unitScaleToMM: scale, unitsAssumed: assumed))
                let adjacency = try collectEdges(bodyID: bodyID)
                model.reachableEdgeCount += adjacency.count
                for edgeID in adjacency.keys.sorted() {
                    try Task.checkCancellation()
                    do {
                        let edge = try edge(edgeID, body: identity, resolver: resolver, faces: adjacency[edgeID]!.sorted())
                        model.edges.append(edge)
                        for point in edge.points {
                            if model.bounds == nil { model.bounds = STEPBounds(min: point, max: point) }
                            else { model.bounds?.include(point) }
                        }
                    } catch let error as STEPParseError {
                        diagnose(edgeID, error.description)
                    }
                }
            }
        }
        if model.bodies.isEmpty { diagnose(nil, "No supported solid/shell bodies in shape representations") }
        if model.edges.isEmpty { diagnose(nil, "No supported line edges were extracted") }

        return model
    }

    private func diagnose(_ id: Int?, _ message: String) {
        model.diagnostics.append(STEPDiagnostic(entityID: id, message: message))
    }

    private struct Visit: Hashable { let id: Int; let face: Int? }

    private func collectEdges(bodyID: Int) throws -> [Int: Set<Int>] {
        var adjacency: [Int: Set<Int>] = [:]
        var visited: Set<Visit> = []
        func walk(_ id: Int, face: Int?, ancestors: Set<Int>) throws {
            try Task.checkCancellation()
            guard ancestors.count < 128, !ancestors.contains(id) else {
                diagnose(id, "Cyclic/deep topology reference")
                return
            }
            guard visited.insert(Visit(id: id, face: face)).inserted else { return }
            if file.hasType(id, "EDGE_CURVE") {
                if adjacency[id] == nil { adjacency[id] = [] }
                if let face { adjacency[id]?.insert(face) }
                return
            }
            var ancestors = ancestors
            ancestors.insert(id)
            do {
                let components = try file.components(id)
                // Prefer the most derived body type for simple records.
                let supported = Self.bodyTypes.union([
                    "CLOSED_SHELL", "OPEN_SHELL", "ORIENTED_CLOSED_SHELL",
                    "ADVANCED_FACE", "FACE_SURFACE", "FACE_BOUND", "FACE_OUTER_BOUND",
                    "EDGE_LOOP", "ORIENTED_EDGE"
                ])
                guard let part = components.first(where: { supported.contains($0.type) }) else {
                    throw STEPParseError("Unsupported topology at #\(id)")
                }
                let p = part.parameters
                let children: [Int]
                var nextFace = face
                switch part.type {
                    case "MANIFOLD_SOLID_BREP": children = [try p.reference(at: 1)]
                    case "BREP_WITH_VOIDS": children = [try p.reference(at: 1)] + (try p.references(at: 2))
                    case "SHELL_BASED_SURFACE_MODEL", "CLOSED_SHELL", "OPEN_SHELL", "EDGE_LOOP":
                        children = try p.references(at: 1)
                    case "ADVANCED_FACE", "FACE_SURFACE":
                        children = try p.references(at: 1)
                        nextFace = id
                    case "FACE_BOUND", "FACE_OUTER_BOUND": children = [try p.reference(at: 1)]
                    case "ORIENTED_CLOSED_SHELL": children = [try p.reference(at: 2)]
                    case "ORIENTED_EDGE": children = [try p.reference(at: 3)]
                    default: children = []
                }
                for child in children { try walk(child, face: nextFace, ancestors: ancestors) }
            } catch let error as STEPParseError {
                diagnose(id, error.description)
            }
        }
        try walk(bodyID, face: nil, ancestors: [])
        return adjacency
    }

    private func edge(_ id: Int, body: STEPBodyID, resolver: STEPCurveResolver, faces: [Int]) throws -> STEPEdge {
        let p = try file.parameters(id, type: "EDGE_CURVE")
        let start = try p.reference(at: 1)
        let end = try p.reference(at: 2)
        guard let sense = try p.argument(4).enumeration, sense == "T" || sense == "F" else {
            throw STEPParseError("Invalid EDGE_CURVE same_sense")
        }
        // Vertex order is canonical EDGE_CURVE order, independent of ORIENTED_EDGE uses.
        let curve = try resolver.resolve(curveID: p.reference(at: 3), startVertexID: start, endVertexID: end,
                                         sameSense: sense == "T")
        if let warning = curve.warning { diagnose(id, warning) }
        return STEPEdge(id: STEPEdgeID(importID: model.importID, bodyID: body, entityID: id),
                        kind: curve.kind,
                        points: curve.points,
                        startVertexID: start,
                        endVertexID: end,
                        adjacentFaceIDs: faces,
                        chordError: curve.chordError)
    }

    private var angleScales: [Int: Result<Double, STEPParseError>] = [:]

    /// Radians per context angle unit, resolved once per context and only if some edge needs it.
    private func angleScale(context: Int) throws -> Double {
        if let cached = angleScales[context] { return try cached.get() }
        do {
            let scale = try STEPUnits(file: file).angleScaleToRadians(contextID: context)
            angleScales[context] = .success(scale)
            return scale
        } catch let error as STEPParseError {
            angleScales[context] = .failure(error)
            throw error
        }
    }
}
