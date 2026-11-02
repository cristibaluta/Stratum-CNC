import Foundation
import Combine
import simd

struct STEPSourceReference: Identifiable, Sendable {
    let id: UUID
    let name: String
    let url: URL
}

struct STEPViewerContent: Sendable {
    let model: STEPEdgeModel
    let geometry: STEPDisplayGeometry

    static func load(url: URL, importID: UUID) async throws -> STEPViewerContent {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let model = try STEPEdgeImporter.parse(data: Data(contentsOf: url, options: .mappedIfSafe), importID: importID)
            return try STEPViewerContent(model: model, geometry: STEPDisplayGeometry(model: model))
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
}

@MainActor
final class STEPDocumentScene: ObservableObject, Identifiable {
    let id: UUID
    let content: STEPViewerContent
    let baseObjects: [RenderObject]
    @Published private(set) var selectedEdges: Set<STEPEdgeID> = []
    @Published private(set) var hiddenBodies: Set<STEPBodyID> = []
    @Published var isModelVisible = true {
        didSet { if !isModelVisible { clearSelection() } }
    }
    @Published private(set) var selectionObjects: [RenderObject] = []
    @Published var fitRequest = 0

    init(content: STEPViewerContent) {
        id = content.model.importID
        self.content = content
        baseObjects = content.geometry.bodies.map {
            RenderObject(role: .model, points: $0.points, color: CanvasPalette.model, primitive: .lineList)
        }
    }

    var visibleObjects: [RenderObject] {
        guard isModelVisible else { return [] }
        return zip(content.geometry.bodies, baseObjects).compactMap { body, object in
            hiddenBodies.contains(body.id) ? nil : object
        } + selectionObjects
    }

    func setBodyVisible(_ id: STEPBodyID, _ visible: Bool) {
        if visible { hiddenBodies.remove(id) } else {
            hiddenBodies.insert(id)
            selectedEdges = selectedEdges.filter { $0.bodyID != id }
            rebuildHighlight()
        }
    }

    func pick(point: CGPoint, viewport: CGSize, matrix: simd_float4x4, extend: Bool) {
        let hit = isModelVisible ? content.geometry.hitTest(at: point, viewport: viewport, matrix: matrix, hiddenBodies: hiddenBodies) : nil
        select(hit, extend: extend)
    }

    func select(_ id: STEPEdgeID?, extend: Bool) {
        guard let id, isModelVisible, !hiddenBodies.contains(id.bodyID),
              content.geometry.bodies.contains(where: { $0.edges.contains(where: { $0.id == id }) }) else {
            clearSelection()
            return
        }
        if extend {
            if !selectedEdges.insert(id).inserted { selectedEdges.remove(id) }
        } else { selectedEdges = [id] }
        rebuildHighlight()
    }

    func clearSelection() {
        selectedEdges.removeAll()
        selectionObjects.removeAll()
    }

    private func rebuildHighlight() {
        var points: [SIMD3<Float>] = []
        for body in content.geometry.bodies where !hiddenBodies.contains(body.id) {
            for edge in body.edges where selectedEdges.contains(edge.id) {
                points.append(contentsOf: body.points[edge.vertices])
            }
        }
        // A new small overlay buffer, never new identities for the base objects.
        selectionObjects = points.isEmpty ? [] : [RenderObject(role: .modelSelection, points: points,
                                                               color: CanvasPalette.modelSelection, primitive: .lineList)]
    }
}

@MainActor
final class STEPWorkspace: ObservableObject {
    typealias Loader = @Sendable (URL, UUID) async throws -> STEPViewerContent
    @Published private(set) var sources: [STEPSourceReference] = []
    @Published private(set) var documents: [UUID: STEPDocumentScene] = [:]
    @Published private(set) var loadingIDs: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]
    @Published var activeID: UUID?
    @Published var isPresented = false
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]
    private let loader: Loader

    init(loader: @escaping Loader = { try await STEPViewerContent.load(url: $0, importID: $1) }) {
        self.loader = loader
    }

    func load(_ source: STEPSourceReference, onFinished: @escaping @MainActor () -> Void = {}) {
        tasks[source.id]?.cancel()
        let token = UUID()
        tokens[source.id] = token
        if !sources.contains(where: { $0.id == source.id }) { sources.append(source) }
        documents.removeValue(forKey: source.id) // invalidates selection on reload
        errors.removeValue(forKey: source.id)
        loadingIDs.insert(source.id)
        activeID = source.id
        isPresented = true
        let loader = loader
        tasks[source.id] = Task { [weak self] in
            defer { onFinished() }
            do {
                try Task.checkCancellation()
                let content = try await loader(source.url, source.id)
                try Task.checkCancellation()
                guard let self, self.tokens[source.id] == token else { return }
                self.documents[source.id] = STEPDocumentScene(content: content)
                self.finish(source.id)
            } catch {
                guard let self, self.tokens[source.id] == token else { return }
                self.errors[source.id] = error is CancellationError ? "Import cancelled" : String(describing: error)
                self.finish(source.id)
            }
        }
    }

    private func finish(_ id: UUID) {
        loadingIDs.remove(id)
        tokens.removeValue(forKey: id)
        tasks.removeValue(forKey: id)
    }

    func reportFailure(_ source: STEPSourceReference, message: String) {
        tasks[source.id]?.cancel()
        finish(source.id)
        if !sources.contains(where: { $0.id == source.id }) { sources.append(source) }
        documents.removeValue(forKey: source.id)
        errors[source.id] = message
        activeID = source.id
        isPresented = true
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        finish(id)
        errors[id] = "Import cancelled. Retry to load the retained project source."
    }

    func remove(_ id: UUID) {
        tasks[id]?.cancel()
        finish(id)
        documents.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        sources.removeAll { $0.id == id }
        if activeID == id { activeID = sources.last?.id }
        if sources.isEmpty { isPresented = false }
    }

    func clear() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        tokens.removeAll()
        loadingIDs.removeAll()
        documents.removeAll()
        errors.removeAll()
        sources.removeAll()
        activeID = nil
        isPresented = false
    }

    deinit { for task in tasks.values { task.cancel() } }
}
