import Foundation

/// Standalone B-rep parts: line and circular edges (arcs, full circles, trimmed circles).
/// The caller supplies a stable import ID when reparsing an unchanged project source.
enum STEPEdgeImporter {
    static func parse(data: Data, importID: UUID = UUID(), options: STEPImportOptions = STEPImportOptions()) throws -> STEPEdgeModel {
        try Task.checkCancellation()
        let file = try STEPFile(data: data)
        return try STEPEdgeExtractor(file: file, importID: importID, options: options).extract()
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
