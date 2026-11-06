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
    /// Triangles that hide edges behind the part. Empty when a body's faces could not all be
    /// tessellated (see `diagnostics`); that body's edges are then drawn solid, as before.
    var surfaces = STEPSurfaceModel()

    static func load(url: URL, importID: UUID) async throws -> STEPViewerContent {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let imported = try STEPEdgeImporter.parseGeometry(data: Data(contentsOf: url, options: .mappedIfSafe),
                                                              importID: importID)
            return try STEPViewerContent(model: imported.edges,
                                         geometry: STEPDisplayGeometry(model: imported.edges),
                                         surfaces: imported.surfaces)
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

/// How edges behind a face are drawn. Needs the body's surface (`STEPViewerContent.surfaces`);
/// without one every edge is drawn solid.
enum STEPHiddenEdgeMode: String, CaseIterable, Identifiable, Sendable {
    case dotted, hidden, solid

    var id: String { rawValue }

    var label: String {
        switch self {
            case .dotted: return "Dotted"
            case .hidden: return "Hidden"
            case .solid: return "Solid"
        }
    }
}

/// What the part is drawn as. Shaded modes need the body's surface (`STEPViewerContent.surfaces`);
/// a body without one keeps its wireframe in every mode.
enum STEPDisplayMode: String, CaseIterable, Identifiable, Sendable {
    /// Edges only; hidden edges follow `STEPHiddenEdgeMode`.
    case wireframe
    /// Lit faces, no edges (and so nothing to pick until face picking exists).
    case shaded
    /// Lit faces with the edges on top; hidden edges follow `STEPHiddenEdgeMode`.
    case shadedEdges

    var id: String { rawValue }

    var label: String {
        switch self {
            case .wireframe: return "Wireframe"
            case .shaded: return "Shaded"
            case .shadedEdges: return "Shaded + edges"
        }
    }
}

@MainActor
final class STEPDocumentScene: ObservableObject, Identifiable {
    let id: UUID
    let content: STEPViewerContent
    @Published private(set) var baseObjects: [RenderObject]
    /// One lit-triangle object per body with a surface, in the same body order as `baseObjects`
    /// (`nil` where the body has none or the mode draws no faces).
    @Published private(set) var solidObjects: [RenderObject?]
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

    /// Models with more triangles than this stay wireframe: lit faces need a CPU and a GPU copy
    /// of every triangle, unindexed, about 100 bytes each.
    static let defaultShadedTriangleCap = 500_000
    private static let displayModeKey = "STEPDisplayMode"
    private let shadedTriangleCap: Int
    private let defaults: UserDefaults?

    /// Edges behind a face: dotted (the default when the part has surfaces), not drawn, or drawn
    /// solid like a plain wireframe. Only the base objects are rebuilt, never the selection.
    /// Picking stays all-edges in every mode that shows edges, and the selection highlight is drawn
    /// over the whole part, hidden edges included, so a selected rear edge can always be seen.
    @Published var hiddenEdgeMode: STEPHiddenEdgeMode = .solid {
        didSet { if hiddenEdgeMode != oldValue { rebuildObjects() } }
    }

    /// Wireframe, shaded, or shaded with edges. Remembered across sessions. Setting a shaded mode
    /// on a model that cannot be shaded (`canShade`) is ignored.
    @Published var displayMode: STEPDisplayMode = .wireframe {
        didSet {
            guard displayMode != oldValue else { return }
            if displayMode != .wireframe, !canShade {
                displayMode = .wireframe
                return
            }
            defaults?.set(displayMode.rawValue, forKey: Self.displayModeKey)
            // Edges are not drawn, so a plain selection has nothing to show. A toolpath being edited keeps its edges.
            if displayMode == .shaded, !isPicking { setSelection([], notify: true) }
            rebuildObjects()
        }
    }

    /// At least one body has a surface, so the hidden-edge mode has an effect.
    var hasSurfaces: Bool { !content.surfaces.bodies.isEmpty }

    /// Shaded modes are available: surfaces exist and the triangle count is within the cap.
    var canShade: Bool { hasSurfaces && content.surfaces.triangleCount <= shadedTriangleCap }

    /// Why shaded modes are unavailable, for the panel; `nil` when they are available.
    var shadedUnavailableReason: String? {
        if !hasSurfaces { return "Needs every face of a body to be supported; see Details." }
        if content.surfaces.triangleCount > shadedTriangleCap {
            return "Too many triangles to shade (\(content.surfaces.triangleCount) of \(shadedTriangleCap)); showing wireframe."
        }
        return nil
    }

    init(content: STEPViewerContent, offset: SIMD3<Float> = .zero,
         shadedTriangleCap: Int = STEPDocumentScene.defaultShadedTriangleCap,
         defaults: UserDefaults? = .standard) {
        id = content.model.importID
        self.content = content
        self.offset = offset
        self.shadedTriangleCap = shadedTriangleCap
        self.defaults = defaults
        let hidden: STEPHiddenEdgeMode = content.surfaces.bodies.isEmpty ? .solid : .dotted
        var mode: STEPDisplayMode = .wireframe
        if !content.surfaces.bodies.isEmpty, content.surfaces.triangleCount <= shadedTriangleCap,
           let stored = defaults?.string(forKey: Self.displayModeKey), let restored = STEPDisplayMode(rawValue: stored) {
            mode = restored
        }
        hiddenEdgeMode = hidden
        displayMode = mode
        let objects = Self.makeObjects(content, isDark: true, offset: offset, displayMode: mode, hiddenMode: hidden)
        baseObjects = objects.lines
        solidObjects = objects.solids
    }

    /// Moves the model: its edges, faces and the selection overlay are rebuilt translated.
    func setOffset(_ newOffset: SIMD3<Float>) {
        guard newOffset != offset else { return }
        offset = newOffset
        rebuildObjects()
        rebuildHighlight()
    }

    private func rebuildObjects() {
        let objects = Self.makeObjects(content, isDark: isDarkAppearance, offset: offset,
                                       displayMode: displayMode, hiddenMode: hiddenEdgeMode)
        baseObjects = objects.lines
        solidObjects = objects.solids
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

    /// Edges drawn over lit faces: near black reads on the mid-grey faces in both themes.
    private static let edgeOnFacesColor = SIMD4<Float>(0.05, 0.07, 0.10, 1)

    /// Neutral face material that works on a light and on a dark canvas.
    private static func materialColor(isDark: Bool) -> SIMD4<Float> {
        isDark ? SIMD4<Float>(0.56, 0.61, 0.69, 1) : SIMD4<Float>(0.70, 0.74, 0.80, 1)
    }

    /// One line object per body, and for shaded modes one lit-triangle object per body that has a
    /// surface. Wireframe: the surface rides along as depth-only occluders so hidden edges can be
    /// dotted. Shaded: the faces themselves provide the depth, the lines are kept (for the camera fit
    /// and picking data) but not drawn. A body without a surface always keeps its drawn wireframe.
    private static func makeObjects(_ content: STEPViewerContent, isDark: Bool, offset: SIMD3<Float>,
                                    displayMode: STEPDisplayMode, hiddenMode: STEPHiddenEdgeMode)
        -> (lines: [RenderObject], solids: [RenderObject?]) {
        var lines: [RenderObject] = []
        var solids: [RenderObject?] = []
        for body in content.geometry.bodies {
            let points = offset == .zero ? body.points : body.points.map { $0 + offset }
            let mesh = content.surfaces.mesh(for: body.id)
            let shaded = displayMode != .wireframe && mesh != nil
            let color = shaded ? edgeOnFacesColor : modelColor(isDark: isDark)
            var line = RenderObject(role: .model, points: points, color: color, primitive: .lineList)
            var solid: RenderObject?
            if let mesh {
                let style: HiddenLineStyle = hiddenMode == .solid ? .roleDefault : (hiddenMode == .dotted ? .dotted : .omitted)
                switch displayMode {
                    case .wireframe:
                        if hiddenMode != .solid {
                            line.occluderFaces = mesh.occluderTriangles(offset: offset)
                            line.hiddenLineStyle = style
                        }
                    case .shadedEdges:
                        line.hiddenLineStyle = style
                    case .shaded:
                        line.visibleVertexCount = 0
                }
                if displayMode != .wireframe {
                    var triangles: [SolidVertex] = []
                    triangles.reserveCapacity(mesh.indices.count)
                    for index in mesh.indices {
                        triangles.append(SolidVertex(position: mesh.positions[Int(index)] + offset,
                                                     normal: mesh.normals[Int(index)]))
                    }
                    solid = RenderObject(role: .model, points: [], color: materialColor(isDark: isDark),
                                         primitive: .lineList, solidTriangles: triangles)
                }
            }
            lines.append(line)
            solids.append(solid)
        }
        return (lines, solids)
    }

    private var isDarkAppearance = true

    /// Rebuilds the edges in the color that suits the current appearance.
    func setAppearance(isDark: Bool) {
        guard isDark != isDarkAppearance else { return }
        isDarkAppearance = isDark
        rebuildObjects()
    }

    var visibleObjects: [RenderObject] {
        guard isModelVisible else { return [] }
        var objects: [RenderObject] = []
        for (index, body) in content.geometry.bodies.enumerated() where !hiddenBodies.contains(body.id) {
            if let solid = solidObjects[index] { objects.append(solid) }
            objects.append(baseObjects[index])
        }
        return objects + selectionObjects
    }

    func setBodyVisible(_ id: STEPBodyID, _ visible: Bool) {
        if visible { hiddenBodies.remove(id) } else {
            hiddenBodies.insert(id)
            setSelection(selectedEdges.filter { $0.bodyID != id }, notify: true)
        }
    }

    /// The edge under `point`, if any.
    func edge(at point: CGPoint, viewport: CGSize, matrix: simd_float4x4) -> STEPEdgeID? {
        // The geometry is stored at the origin; the matrix the canvas hands over
        // sees it moved, so move it back into place first.
        // Faces cannot be picked yet, and edges that are not drawn must not be either.
        isModelVisible && displayMode != .shaded
            ? content.geometry.hitTest(at: point, viewport: viewport, matrix: matrix * Self.translation(offset),
                                       hiddenBodies: hiddenBodies)
            : nil
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
    }

    deinit { for task in tasks.values { task.cancel() } }
}
