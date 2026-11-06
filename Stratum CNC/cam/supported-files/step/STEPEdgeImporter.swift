import Foundation

/// Both stages of an import: the wireframe and, per body, the triangles that hide its edges.
struct STEPGeometry: Sendable {
    let edges: STEPEdgeModel
    let surfaces: STEPSurfaceModel
}

/// Standalone B-rep parts: line and circular edges (arcs, full circles, trimmed circles).
/// The caller supplies a stable import ID when reparsing an unchanged project source.
enum STEPEdgeImporter {
    static func parse(data: Data, importID: UUID = UUID(), options: STEPImportOptions = STEPImportOptions()) throws -> STEPEdgeModel {
        try Task.checkCancellation()
        let file = try STEPFile(data: data)
        return try STEPEdgeExtractor(file: file, importID: importID, options: options).extract()
    }

    /// Edges plus the surface mesh that lets the viewer draw hidden edges dotted. Parses the file
    /// once and shares it between both stages. Synchronous: call it from a background task.
    static func parseGeometry(data: Data, importID: UUID = UUID(), options: STEPImportOptions = STEPImportOptions()) throws -> STEPGeometry {
        try Task.checkCancellation()
        let file = try STEPFile(data: data)
        let edges = try STEPEdgeExtractor(file: file, importID: importID, options: options).extract()
        // Surfaces only add hidden-edge display: if they cannot be built the wireframe still loads.
        // Cancellation is not a failure to degrade from, so it propagates.
        let surfaces: STEPSurfaceModel
        do {
            surfaces = try STEPTessellator(file: file, model: edges, options: options).tessellate()
        } catch let error as STEPParseError {
            var unavailable = STEPSurfaceModel()
            unavailable.diagnostics = [STEPDiagnostic(entityID: nil, message: "Surfaces unavailable: \(error.description)")]
            surfaces = unavailable
        }
        return STEPGeometry(edges: edges, surfaces: surfaces)
    }

    static func importFile(at url: URL, importID: UUID = UUID(), options: STEPImportOptions = STEPImportOptions()) async throws -> STEPEdgeModel {
        try Task.checkCancellation()
        // Detached deliberately: a Task created by CAMModel would inherit MainActor.
        // The parser/cache are created inside this worker and never cross actors.
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return try parse(data: data, importID: importID, options: options)
        }
        return try await withTaskCancellationHandler {
            let model = try await worker.value
            try Task.checkCancellation()
            return model
        } onCancel: {
            worker.cancel()
        }
    }
}
