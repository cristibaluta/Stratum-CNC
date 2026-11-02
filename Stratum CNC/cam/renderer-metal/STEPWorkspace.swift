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
        } onCancel: {
            worker.cancel()
        }
    }
}

@MainActor
final class STEPDocumentScene: ObservableObject, Identifiable {
    let id: UUID
    let content: STEPViewerContent
    @Published private(set) var baseObjects: [RenderObject]
    @Published private(set) var selectedEdges: Set<STEPEdgeID> = []
    @Published private(set) var hiddenBodies: Set<STEPBodyID> = []
    /// Where the model sits on the canvas, in mm. The model's own corner (min X,
    /// min Y) and top (max Z) are at 0, so this is the position of that corner
    /// and of the top surface. Changed through `STEPWorkspace.setPosition`.
    @Published private(set) var offset: SIMD3<Float>
    @Published var isModelVisible = true {
        // Hiding the model drops a plain selection. A toolpath being edited keeps its edges.
        didSet { if !isModelVisible, !isPicking { setSelection([], notify: false) } }
    }
    /// A toolpath is open: clicks add and remove edges from it (see `STEPWorkspace.beginPicking`).
    private(set) var isPicking = false
    /// Called with the whole selection after every change made by the user while picking.
    var onSelectionChanged: ((Set<STEPEdgeID>) -> Void)?
    /// Bounding box of the selected edges in canvas mm, to anchor the "Add toolpath" tooltip.
    @Published private(set) var selectionBox: (min: SIMD3<Float>, max: SIMD3<Float>)?
    @Published private(set) var selectionObjects: [RenderObject] = []
    /// Draw the selected edges flattened onto the z0 plane (blue, dotted), with
    /// vertical drop lines from their endpoints.
    @Published var showsProjection = true { didSet { rebuildHighlight() } }
    /// Lowest and highest Z of the selected edges, in display coordinates
    /// (the model's top is z0). `nil` when nothing is selected.
    @Published private(set) var selectionZRange: ClosedRange<Float>?
    @Published var fitRequest = 0

    init(content: STEPViewerContent, offset: SIMD3<Float> = .zero) {
        id = content.model.importID
        self.content = content
        self.offset = offset
        baseObjects = Self.makeBaseObjects(content, isDark: true, offset: offset)
    }

    /// Moves the model: its edges and the selection overlay are rebuilt translated.
    func setOffset(_ newOffset: SIMD3<Float>) {
        guard newOffset != offset else { return }
        offset = newOffset
        baseObjects = Self.makeBaseObjects(content, isDark: isDarkAppearance, offset: newOffset)
        rebuildHighlight()
    }

    private static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
        return matrix
    }

    /// Edge color follows the canvas background: light edges on dark, dark on light.
    private static func modelColor(isDark: Bool) -> SIMD4<Float> {
        isDark ? CanvasPalette.model : SIMD4<Float>(0.12, 0.22, 0.38, 1)
    }

    private static func makeBaseObjects(_ content: STEPViewerContent, isDark: Bool,
                                        offset: SIMD3<Float>) -> [RenderObject] {
        content.geometry.bodies.map {
            let points = offset == .zero ? $0.points : $0.points.map { $0 + offset }
            return RenderObject(role: .model, points: points, color: modelColor(isDark: isDark), primitive: .lineList)
        }
    }

    private var isDarkAppearance = true

    /// Rebuilds the edges in the color that suits the current appearance.
    func setAppearance(isDark: Bool) {
        guard isDark != isDarkAppearance else { return }
        isDarkAppearance = isDark
        baseObjects = Self.makeBaseObjects(content, isDark: isDark, offset: offset)
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
            setSelection(selectedEdges.filter { $0.bodyID != id }, notify: true)
        }
    }

    func pick(point: CGPoint, viewport: CGSize, matrix: simd_float4x4, extend: Bool) {
        // The geometry is stored at the origin; the matrix the canvas hands over
        // sees it moved, so move it back into place first.
        let hit = isModelVisible
            ? content.geometry.hitTest(at: point, viewport: viewport, matrix: matrix * Self.translation(offset),
                                       hiddenBodies: hiddenBodies)
            : nil
        select(hit, extend: extend)
    }

    func select(_ id: STEPEdgeID?, extend: Bool) {
        guard let id, isModelVisible, !hiddenBodies.contains(id.bodyID),
              content.geometry.bodies.contains(where: { $0.edges.contains(where: { $0.id == id }) }) else {
            // Like the 2D canvas: an empty click keeps the toolpath's shapes while picking
            if !isPicking { clearSelection() }
            return
        }
        var selection = selectedEdges
        if extend || isPicking {
            if !selection.insert(id).inserted { selection.remove(id) }
        } else {
            selection = [id]
        }
        setSelection(selection, notify: true)
    }

    func clearSelection() {
        setSelection([], notify: true)
    }

    private func setSelection(_ edges: Set<STEPEdgeID>, notify: Bool) {
        selectedEdges = edges
        rebuildHighlight()
        if notify { onSelectionChanged?(edges) }
    }

    /// A toolpath was opened: show its edges as the selection, and from now on every click
    /// toggles an edge of that toolpath.
    func beginPicking(selection: Set<STEPEdgeID>) {
        isPicking = true
        setSelection(selection, notify: false)
    }

    func endPicking() {
        isPicking = false
        onSelectionChanged = nil
        setSelection([], notify: false)
    }

    private static let projectionColor = SIMD4<Float>(0.15, 0.45, 1.0, 1)
    /// Dash and gap length (mm) of the projection lines: a fine dotted line.
    private static let projectionDash: Float = 0.5

    private func rebuildHighlight() {
        var points: [SIMD3<Float>] = []
        var projected: [SIMD3<Float>] = []   // the edges flattened onto z0
        var drops: [SIMD3<Float>] = []       // pairs: edge endpoint, same x/y at z0
        var dropped = Set<SIMD3<Float>>()
        var zMin = Float.infinity, zMax = -Float.infinity
        var boxMin = SIMD3<Float>(repeating: .infinity), boxMax = SIMD3<Float>(repeating: -.infinity)

        for body in content.geometry.bodies where !hiddenBodies.contains(body.id) {
            for edge in body.edges where selectedEdges.contains(edge.id) {
                let edgePoints = body.points[edge.vertices].map { $0 + offset }
                points.append(contentsOf: edgePoints)
                let edgeMin = edgePoints.map(\.z).min() ?? 0
                let edgeMax = edgePoints.map(\.z).max() ?? 0
                zMin = min(zMin, edgeMin)
                zMax = max(zMax, edgeMax)
                for point in edgePoints {
                    boxMin = simd_min(boxMin, point)
                    boxMax = simd_max(boxMax, point)
                }

                // An edge that already lies on z0 is its own projection.
                guard max(abs(edgeMin), abs(edgeMax)) > 1e-4 else { continue }
                projected.append(contentsOf: edgePoints.map { SIMD3<Float>($0.x, $0.y, 0) })
                if let first = edgePoints.first, let last = edgePoints.last {
                    for end in (first == last ? [first] : [first, last])
                    where abs(end.z) > 1e-4 && dropped.insert(end).inserted {
                        drops.append(end)
                        drops.append(SIMD3<Float>(end.x, end.y, 0))
                    }
                }
            }
        }

        // New small overlay buffers, never new identities for the base objects.
        // The projection goes first so the orange selection stays on top of it.
        var objects: [RenderObject] = []
        if showsProjection {
            for line in [projected, drops] where !line.isEmpty {
                objects.append(RenderObject(role: .modelSelection, points: line,
                                            color: Self.projectionColor, primitive: .lineList,
                                            isDashed: true, dashLength: Self.projectionDash))
            }
        }
        if !points.isEmpty {
            objects.append(RenderObject(role: .modelSelection, points: points,
                                        color: CanvasPalette.modelSelection, primitive: .lineList))
        }
        selectionObjects = objects
        selectionZRange = points.isEmpty ? nil : zMin...zMax
        selectionBox = points.isEmpty ? nil : (boxMin, boxMax)
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
    /// The model selected in the objects list, whose position the inspector edits.
    @Published var selectedModelID: UUID?
    /// Where each source sits, kept here (not in the scene) so a reload keeps it.
    private var offsets: [UUID: SIMD3<Float>] = [:]
    /// A model moved: toolpaths cut from its edges are outdated.
    var onModelMoved: (() -> Void)?
    /// The open toolpath's edges and where edits go; set while a toolpath is open.
    private var picking: (targets: [STEPEdgeTarget], onChange: (UUID, Set<STEPEdgeID>) -> Void)?
    /// Called after the user moved a model, so the project can save it.
    var onOffsetChanged: (@MainActor (UUID, SIMD3<Float>) -> Void)?
    /// True while the CAM canvas is in 3D (STEP) mode instead of the 2D design mode.
    @Published var isPresented = false
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]
    private let loader: Loader

    /// The scene of the active source, once it has finished loading.
    var activeScene: STEPDocumentScene? { activeID.flatMap { documents[$0] } }

    init(loader: @escaping Loader = { try await STEPViewerContent.load(url: $0, importID: $1) }) {
        self.loader = loader
    }

    func position(of id: UUID) -> SIMD3<Float> { offsets[id] ?? .zero }

    /// Puts a saved position back before the source loads. Not a user edit.
    func restorePosition(_ position: SIMD3<Float>, for id: UUID) {
        offsets[id] = position
        documents[id]?.setOffset(position)
    }

    func setPosition(_ position: SIMD3<Float>, for id: UUID) {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              position != self.position(of: id) else { return }
        offsets[id] = position
        documents[id]?.setOffset(position)
        objectWillChange.send()
        onModelMoved?()
        onOffsetChanged?(id, position)
    }

    /// A toolpath was opened: its edges become the selection of their models, and clicking an
    /// edge adds it to or removes it from the toolpath (`onChange` gets the model and its
    /// whole selection). Models that finish loading later join in.
    func beginPicking(targets: [STEPEdgeTarget], onChange: @escaping (UUID, Set<STEPEdgeID>) -> Void) {
        endPicking()
        picking = (targets, onChange)
        for scene in documents.values { attachPicking(to: scene) }
    }

    func endPicking() {
        picking = nil
        for scene in documents.values { scene.endPicking() }
    }

    private func attachPicking(to scene: STEPDocumentScene) {
        guard let picking else { return }
        let importID = scene.id
        scene.onSelectionChanged = { ids in picking.onChange(importID, ids) }
        scene.beginPicking(selection: Set(picking.targets.filter { $0.importID == importID }.map(\.edgeID)))
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
                let scene = STEPDocumentScene(content: content, offset: self.offsets[source.id] ?? .zero)
                self.documents[source.id] = scene
                self.attachPicking(to: scene)
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
        offsets.removeValue(forKey: id)
        if selectedModelID == id { selectedModelID = nil }
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
        offsets.removeAll()
        picking = nil
        selectedModelID = nil
        activeID = nil
        isPresented = false
    }

    deinit { for task in tasks.values { task.cancel() } }
}
