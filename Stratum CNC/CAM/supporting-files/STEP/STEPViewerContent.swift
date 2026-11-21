//
//  STEPViewerContent.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.11.2026.
//

import Foundation
import simd
import SwiftSTEP

struct STEPViewerContent: Sendable {
    let importID: UUID
    /// The bodies as read from the file, each in its own frame, before it is turned or scaled.
    private(set) var importedGeometry: STEPDisplayGeometry
    /// The bodies as they are on the canvas: each one scaled and turned so that its `orientation` faces up.
    private(set) var geometry: STEPDisplayGeometry
    /// Triangles that hide edges behind the part. A body that could not be tessellated completely has a
    /// partial mesh or none (see `diagnostics`); its edges are then drawn solid, as before.
    /// They stay in the file's frame: a body's `placement` takes them to where its `geometry` is.
    var surfaces = STEP.SurfaceModel()
    /// The bodies, in the file's order. A deleted body is gone from here.
    private(set) var infos: [STEPBodyInfo]
    /// How many bodies the file had before any was deleted: the list numbers them only when it is more than one.
    let bodyCount: Int
    let edgeCount: Int
    let skippedEdgeCount: Int
    let diagnostics: [STEP.Diagnostic]
    private(set) var orientations: [STEP.BodyID: SetupFace] = [:]
    private(set) var scales: [STEP.BodyID: Float] = [:]
    private(set) var placements: [STEP.BodyID: STEPPlacement] = [:]
    private(set) var sizes: [STEP.BodyID: SIMD3<Float>] = [:]

    init(importID: UUID,
         geometry: STEPDisplayGeometry,
         surfaces: STEP.SurfaceModel = STEP.SurfaceModel(),
         labels: [STEP.BodyID: String] = [:],
         edgeCount: Int = 0,
         skippedEdgeCount: Int = 0,
         diagnostics: [STEP.Diagnostic] = []) {

        self.importID = importID
        self.importedGeometry = geometry
        self.geometry = geometry
        self.surfaces = surfaces
        self.edgeCount = edgeCount
        self.skippedEdgeCount = skippedEdgeCount
        self.diagnostics = diagnostics
        bodyCount = geometry.bodies.count
        var infos: [STEPBodyInfo] = []
        var placements: [STEP.BodyID: STEPPlacement] = [:]
        var sizes: [STEP.BodyID: SIMD3<Float>] = [:]


        for (index, body) in geometry.bodies.enumerated() {
            let position = SIMD3<Float>(body.origin - geometry.origin)
            infos.append(STEPBodyInfo(id: body.id, number: index + 1, label: labels[body.id], defaultPosition: position))
            // The mesh is measured from the file's origin, the edges from the body's own corner
            placements[body.id] = STEPPlacement(rotation: matrix_identity_float3x3, shift: .zero, anchor: -position)
            sizes[body.id] = Self.size(of: body)
        }
        self.infos = infos
        self.placements = placements
        self.sizes = sizes
    }

    /// An import of a file's bodies, placed in the file's coordinates (assemblies applied).
    init(assembly: STEP.Assembly) throws {
        let geometry = try STEPDisplayGeometry(bodies: assembly.bodies,
                                               origin: STEPDisplayGeometry.displayOrigin(bounds: assembly.bounds))
        var labels: [STEP.BodyID: String] = [:]
        for body in assembly.bodies {
            let parts = body.path + (body.name.map { [$0] } ?? [])
            if !parts.isEmpty {
                labels[body.id] = parts.joined(separator: " / ")
            }
        }
        self.init(importID: assembly.importID, geometry: geometry, surfaces: assembly.surfaces, labels: labels,
                  edgeCount: assembly.edgeCount, skippedEdgeCount: assembly.skippedEdgeCount,
                  diagnostics: assembly.diagnostics)
    }

    func info(of id: STEP.BodyID) -> STEPBodyInfo? {
        infos.first { $0.id == id }
    }

    /// Which face of the body faces up.
    func orientation(of id: STEP.BodyID) -> SetupFace {
        orientations[id] ?? .top
    }

    func scale(of id: STEP.BodyID) -> Float {
        scales[id] ?? 1
    }

    func placement(of id: STEP.BodyID) -> STEPPlacement {
        placements[id] ?? .identity
    }

    /// Width (X), depth (Y) and height (Z) of the body as it sits (turned and scaled), in mm.
    /// `nil` for a body that is not in the content.
    func size(of id: STEP.BodyID) -> SIMD3<Float>? {
        sizes[id]
    }

    /// The same content with the body turned so `face` faces up, and scaled by `scale`. Always starts
    /// from the imported geometry, so turning back to `.top` at scale 1 is exact.
    func updated(_ id: STEP.BodyID, orientation face: SetupFace, scale: Float) -> STEPViewerContent {

        guard let imported = importedGeometry.bodies.first(where: { $0.id == id }),
              let bodyInfo = self.info(of: id),
              let index = geometry.bodies.firstIndex(where: { $0.id == id }) else {
            return self
        }
        var content = self
        let rotation = face.modelRotation
        var body = imported
        var shift = SIMD3<Float>.zero

        if face != .top || scale != 1 {
            let placed = imported.placed(rotation: rotation, scale: scale)
            body = placed.body
            shift = placed.shift
        }
        content.geometry.bodies[index] = body
        content.placements[id] = STEPPlacement(rotation: rotation, shift: shift,
                                               anchor: -bodyInfo.defaultPosition, scale: scale)
        content.orientations[id] = face
        content.scales[id] = scale
        content.sizes[id] = Self.size(of: body)

        return content
    }

    /// The same content without the body.
    func removing(_ id: STEP.BodyID) -> STEPViewerContent {
        var content = self
        content.importedGeometry.bodies.removeAll { $0.id == id }
        content.geometry.bodies.removeAll { $0.id == id }
        content.infos.removeAll { $0.id == id }
        content.orientations.removeValue(forKey: id)
        content.scales.removeValue(forKey: id)
        content.placements.removeValue(forKey: id)
        content.sizes.removeValue(forKey: id)


        return content
    }

    private static func size(of body: STEPDisplayGeometry.Body) -> SIMD3<Float> {
        var low = SIMD3<Float>(repeating: .infinity)
        var high = SIMD3<Float>(repeating: -.infinity)
        for point in body.points {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        guard low.x.isFinite, high.x.isFinite else {
            return .zero
        }
        return high - low
    }

    static func load(url: URL, importID: UUID) async throws -> STEPViewerContent {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let assembly: STEP.Assembly
            if url.pathExtension.lowercased() == "stl" {
                // A mesh file: one body. STL has no edges of its own, so the library derives them
                // (creases sharper than 30° and open boundaries), which is also what the body is
                // measured and drawn from. No units either: the library's default (mm) applies.
                assembly = try await STL.loadAssembly(contentsOf: url, importID: importID,
                                                      stl: STL.Options(featureAngleDegrees: 30, smoothShading: true))
            } else {
                // `readAssembly`, not `readGeometry`: one `Body` per solid, and an assembly's parts placed.
                assembly = try STEP.readAssembly(data: Data(contentsOf: url, options: .mappedIfSafe),
                                                 importID: importID)
            }
            return try STEPViewerContent(assembly: assembly)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }
}
