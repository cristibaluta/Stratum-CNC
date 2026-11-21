import Foundation
import Combine
import simd
import SwiftSTEP
import StratumCAM

struct STEPSourceReference: Identifiable, Sendable {
    let id: UUID
    let name: String
    let url: URL
}

/// Fires whenever any scene of the workspace changes (edges, faces, selection, visibility, display
/// options), so a view that draws every loaded scene watches this one object instead of one scene.
/// It is separate from the workspace's own `objectWillChange` on purpose: a selection must repaint
/// the canvas without also re-rendering everything that observes the workspace (the CAM model forwards it).
@MainActor
final class STEPSceneChanges: ObservableObject {
    func send() {
        objectWillChange.send()
    }
}

/// One body of a STEP file, as the objects list shows it.
struct STEPBodyInfo: Sendable, Identifiable {
    let id: STEP.BodyID
    /// 1-based, in the file's order: "Body 2" in the objects list.
    let number: Int
    /// The occurrence path and name the file gives the body (`Gearbox / Shaft / Die`); `nil` when it has none.
    let label: String?
    /// Where the body sits, relative to the whole file's corner (min X, min Y) and top (max Z), when
    /// nothing has been moved: the arrangement the file describes.
    let defaultPosition: SIMD3<Float>
}

/// What the user did to one body of a file, saved with the project (see `AssetData.stepBodies`).
/// Everything is optional: a body nobody touched has no state at all.
struct STEPBodyState: Codable, Hashable, Sendable {
    /// Where the body's corner and top sit on the canvas: x, y and z in mm.
    var position: [Double]?
    /// `SetupFace.persistedName`; `nil` is the top.
    var face: String?
    /// Uniform scale; `nil` is 1.
    var scale: Double?
    /// The body was deleted from the objects list. It stays in the file, so this is what keeps it out.
    var isRemoved: Bool?
}

extension STEP.BodyID {
    /// The key of the body's saved state: stable for the same file.
    var stateKey: String {
        "\(representationID).\(entityID).\(instance)"
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

    /// Changes inside any loaded scene (see `STEPSceneChanges`).
    let sceneChanges = STEPSceneChanges()
    private var sceneObservers: [UUID: AnyCancellable] = [:]
    /// The model selected in the objects list, whose position the inspector edits.
    @Published var selectedModelID: UUID?
    /// Where a file as a whole sat in projects saved before the bodies could be moved one by one. A body
    /// with no position of its own starts there, shifted by its place in the file's arrangement.
    private var legacyOffsets: [UUID: SIMD3<Float>] = [:]
    /// Likewise the face that faced up for a whole file: the face of every body with no saved face of its own.
    private var legacyFaces: [UUID: SetupFace] = [:]
    /// What the user did to each body of each file (`STEP.BodyID.stateKey`). Kept here, not in the scene,
    /// so a reload keeps it, and so it can be put back before a file has loaded.
    private var bodyStates: [UUID: [String: STEPBodyState]] = [:]
    /// A body of a file: what a row of the objects list stands for.
    private struct ModelKey: Hashable {
        let source: UUID
        let body: STEP.BodyID
    }
    /// The id of each body's row. Made up when the file loads and kept for as long as the workspace
    /// lives (it is never saved: a body is saved by its `stateKey`).
    private var modelIDs: [ModelKey: UUID] = [:]
    private var modelKeys: [UUID: ModelKey] = [:]
    /// Called after the user moved, turned, scaled or deleted a body, so the project can save it:
    /// the file, the body's `stateKey` and its whole state.
    var onBodyStateChanged: (@MainActor (UUID, String, STEPBodyState) -> Void)?
    /// The open toolpath's edges and where edits go; set while a toolpath is open.
    private var picking: (targets: [STEPEdgeTarget], onChange: (UUID, Set<STEP.EdgeID>) -> Void)?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]
    private let loader: Loader

    /// The scene of the active source, once it has finished loading.
    var activeScene: STEPDocumentScene? {
        activeID.flatMap { documents[$0] }
    }

    /// Every file that has finished loading, in the order they were added. The canvas draws all of
    /// them at once: selecting a row only chooses what is selected, never what is shown.
    var loadedScenes: [STEPDocumentScene] {
        sources.compactMap { documents[$0.id] }
    }

    private func observe(_ scene: STEPDocumentScene, for source: UUID) {
        sceneObservers[source] = scene.objectWillChange
            .sink { [weak self] _ in
                self?.sceneChanges.send()
            }
    }

    init(loader: @escaping Loader = { try await STEPViewerContent.load(url: $0, importID: $1) }) {
        self.loader = loader
    }

    // MARK: Models
    //
    // A "model" is what a row of the objects list stands for, and its id is a `UUID`: a body of a
    // loaded file, or the whole file while it is loading or when it failed to load (then the id is
    // the source's own). Moving, turning, scaling, hiding and deleting act on one body.

    /// A row of the objects list.
    struct ModelEntry: Identifiable {
        let id: UUID
        let sourceID: UUID
        /// `nil` for a file that has not loaded (or has no bodies): the row stands for the whole file.
        let body: STEP.BodyID?
        /// "plate.step · Body 2" for a file of several bodies, the file's name otherwise.
        let name: String
        /// What the file calls the body (occurrence path and name), for the row's tooltip.
        let detail: String?
    }

    /// The rows of the objects list: every body of every loaded file, in the file's order.
    var modelEntries: [ModelEntry] {
        var entries: [ModelEntry] = []
        for source in sources {
            guard let scene = documents[source.id], !scene.content.infos.isEmpty else {
                entries.append(ModelEntry(id: source.id, sourceID: source.id, body: nil, name: source.name, detail: nil))
                continue
            }
            let numbered = scene.content.bodyCount > 1
            for info in scene.content.infos {
                entries.append(ModelEntry(id: modelID(source: source.id, body: info.id), sourceID: source.id,
                                          body: info.id,
                                          name: numbered ? "\(source.name) · Body \(info.number)" : source.name,
                                          detail: info.label))
            }
        }
        return entries
    }

    private func modelID(source: UUID, body: STEP.BodyID) -> UUID {
        let key = ModelKey(source: source, body: body)
        if let id = modelIDs[key] {
            return id
        }
        let id = UUID()
        modelIDs[key] = id
        modelKeys[id] = key

        return id
    }

    /// The body a row stands for; `nil` for the row of a file that has not loaded.
    func body(ofModel id: UUID) -> STEP.BodyID? {
        modelKeys[id]?.body
    }

    /// The file a row belongs to; `nil` for an id that is not a model.
    func sourceID(ofModel id: UUID) -> UUID? {
        if let key = modelKeys[id] {
            return key.source
        }
        return sources.contains(where: { $0.id == id }) ? id : nil
    }

    /// The scene that holds a row's body; `nil` for a file that has not loaded.
    func scene(ofModel id: UUID) -> STEPDocumentScene? {
        sourceID(ofModel: id).flatMap { documents[$0] }
    }

    /// How many bodies the file still shows; 0 while it has not loaded.
    func remainingBodies(inSource id: UUID) -> Int {
        documents[id]?.content.infos.count ?? 0
    }

    /// A row was clicked: it is the selected model, and its file is the one on the canvas.
    func select(model id: UUID) {
        selectedModelID = id
        if let source = sourceID(ofModel: id) {
            activeID = source
        }
    }

    private func resolve(_ model: UUID) -> (key: ModelKey, scene: STEPDocumentScene)? {
        guard let key = modelKeys[model], let scene = documents[key.source] else {
            return nil
        }
        return (key, scene)
    }

    func isVisible(model id: UUID) -> Bool {
        if let (key, scene) = resolve(id) {
            return scene.isBodyVisible(key.body)
        }
        return documents[id]?.isModelVisible ?? true
    }

    func toggleVisibility(of id: UUID) {
        if let (key, scene) = resolve(id) {
            scene.toggleBodyVisible(key.body)
        } else {
            documents[id]?.isModelVisible.toggle()
        }
        objectWillChange.send()
    }

    /// Where the body's corner and top sit on the canvas, in mm.
    func position(of id: UUID) -> SIMD3<Float> {
        guard let (key, scene) = resolve(id) else {
            return .zero
        }
        return scene.position(of: key.body)
    }

    /// Which face of the body faces up; `nil` for a model that is not loaded.
    func orientation(of id: UUID) -> SetupFace? {
        guard let (key, scene) = resolve(id) else {
            return nil
        }
        return scene.content.orientation(of: key.body)
    }

    /// Puts what the project saved back before the file loads. Not a user edit.
    func restoreBodyStates(_ states: [String: STEPBodyState], for source: UUID) {
        bodyStates[source] = states
    }

    /// Puts the saved position of a whole file back before it loads (see `legacyOffsets`). Not a user edit.
    func restoreLegacyOffset(_ offset: SIMD3<Float>, for source: UUID) {
        legacyOffsets[source] = offset
    }

    /// Puts the saved face-up of a whole file back before it loads (see `legacyFaces`). Not a user edit.
    func restoreLegacyFace(_ face: SetupFace, for source: UUID) {
        legacyFaces[source] = face
    }

    /// Records a change of one body: kept for reloads, and reported so the project saves it.
    private func update(_ key: ModelKey, _ change: (inout STEPBodyState) -> Void) {
        var state = bodyStates[key.source]?[key.body.stateKey] ?? STEPBodyState()
        change(&state)
        bodyStates[key.source, default: [:]][key.body.stateKey] = state
        onBodyStateChanged?(key.source, key.body.stateKey, state)
    }

    /// A body changed: toolpaths cut from its edges are outdated.
    private func bodyChanged() {
        objectWillChange.send()
        // TODO: who deleted this? Is it needed?
//        onModelMoved?()
    }

    func setPosition(_ position: SIMD3<Float>, for id: UUID) {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              let (key, scene) = resolve(id), position != scene.position(of: key.body) else {
            return
        }
        scene.setPosition(position, of: key.body)
        update(key) { $0.position = [Double(position.x), Double(position.y), Double(position.z)] }
        bodyChanged()
    }

    /// The user picked which face of the body faces up. Toolpaths cut from its edges are outdated.
    func setOrientation(_ face: SetupFace, for id: UUID) {
        guard let (key, scene) = resolve(id), face != scene.content.orientation(of: key.body) else {
            return
        }
        scene.setOrientation(face, of: key.body)
        // Saved even for the top: a body that was put back must not take the file's old face again
        update(key) { $0.face = face.persistedName }
        bodyChanged()
    }

    /// Scales the body about its corner and top, to this width (X, as it sits). Depth and height follow.
    func setWidth(_ width: Float, for id: UUID) {
        guard width.isFinite, width > 0, let (key, scene) = resolve(id),
              let size = scene.content.size(of: key.body), size.x > 1e-6 else {
            return
        }
        setScale(scene.content.scale(of: key.body) * width / size.x, for: id)
    }

    /// Scales the body by `factor` (×2 is 2, ÷2 is -2), like the 2D objects.
    func scaleModel(_ id: UUID, factor: Int) {
        guard factor != 0, let (key, scene) = resolve(id) else {
            return
        }
        let by = factor > 0 ? Float(factor) : 1 / Float(-factor)
        setScale(scene.content.scale(of: key.body) * by, for: id)
    }

    private func setScale(_ scale: Float, for id: UUID) {
        guard scale.isFinite, let (key, scene) = resolve(id) else {
            return
        }
        let clamped = min(max(scale, 0.001), 1000)
        guard clamped != scene.content.scale(of: key.body) else {
            return
        }
        scene.setScale(clamped, of: key.body)
        update(key) { $0.scale = clamped == 1 ? nil : Double(clamped) }
        bodyChanged()
    }

    /// Takes one body out of its file's scene. Its state remembers it as deleted, so it stays out after
    /// a reload (the file itself is not touched). The last body of a file is not removed here: the project
    /// removes the whole source (`ProjectModel.removeSTEPModel`).
    func removeBody(model id: UUID) {
        guard let (key, scene) = resolve(id), scene.content.infos.count > 1 else {
            return
        }
        scene.removeBody(key.body)
        update(key) { $0.isRemoved = true }
        modelKeys.removeValue(forKey: id)
        modelIDs.removeValue(forKey: key)
        if selectedModelID == id {
            selectedModelID = nil
        }
        bodyChanged()
    }

    /// The scene of a file that has loaded: its bodies turned, scaled and removed as the project saved them,
    /// and each one where it was left, or where the file's arrangement puts it.
    private func makeScene(for source: UUID, content loaded: STEPViewerContent) -> STEPDocumentScene {
        var content = loaded
        let states = bodyStates[source] ?? [:]
        let legacy = legacyOffsets[source] ?? .zero
        let legacyFace = legacyFaces[source] ?? .top
        var positions: [STEP.BodyID: SIMD3<Float>] = [:]

        for info in loaded.infos {
            let state = states[info.id.stateKey]
            if state?.isRemoved == true {
                content = content.removing(info.id)
                continue
            }
            var face = legacyFace
            if let name = state?.face, let saved = SetupFace(persistedName: name) {
                face = saved
            }
            var scale: Float = 1
            if let saved = state?.scale, saved.isFinite, saved > 0 {
                scale = Float(saved)
            }
            if face != .top || scale != 1 {
                content = content.updated(info.id, orientation: face, scale: scale)
            }
            if let saved = state?.position, saved.count == 3 {
                positions[info.id] = SIMD3<Float>(Float(saved[0]), Float(saved[1]), Float(saved[2]))
            } else {
                positions[info.id] = info.defaultPosition + legacy
            }
        }
        for info in content.infos {
            _ = modelID(source: source, body: info.id)
        }

        return STEPDocumentScene(content: content, positions: positions)
    }

    /// A toolpath was opened: its edges become the selection of their models, and clicking an
    /// edge adds it to or removes it from the toolpath (`onChange` gets the model and its
    /// whole selection). Models that finish loading later join in.
    func beginPicking(targets: [STEPEdgeTarget], onChange: @escaping (UUID, Set<STEP.EdgeID>) -> Void) {
        endPicking()
        picking = (targets, onChange)
        for scene in documents.values {
            attachPicking(to: scene)
        }
    }

    func endPicking() {
        picking = nil
        for scene in documents.values {
            scene.endPicking()
        }
    }

    private func attachPicking(to scene: STEPDocumentScene) {
        guard let picking else {
            return
        }
        let importID = scene.id
        scene.onSelectionChanged = { ids in picking.onChange(importID, ids) }
        scene.beginPicking(selection: Set(picking.targets.filter { $0.importID == importID }.map(\.edgeID)))
    }

    func load(_ source: STEPSourceReference, onFinished: @escaping @MainActor () -> Void = {}) {

        tasks[source.id]?.cancel()
        let token = UUID()
        tokens[source.id] = token
        if !sources.contains(where: { $0.id == source.id }) {
            sources.append(source)
        }
        documents.removeValue(forKey: source.id) // invalidates selection on reload
        sceneObservers.removeValue(forKey: source.id)
        errors.removeValue(forKey: source.id)
        loadingIDs.insert(source.id)
        activeID = source.id
        let loader = loader

        tasks[source.id] = Task { [weak self] in
            defer {
                onFinished()
            }
            do {
                try Task.checkCancellation()
                let content = try await loader(source.url, source.id)
                try Task.checkCancellation()
                guard let self, self.tokens[source.id] == token else {
                    return
                }
                let scene = self.makeScene(for: source.id, content: content)
                self.documents[source.id] = scene
                self.observe(scene, for: source.id)
                self.attachPicking(to: scene)
                self.finish(source.id)
                Self.logImport(of: source, content: content)
            } catch {
                guard let self, self.tokens[source.id] == token else {
                    return
                }
                self.errors[source.id] = error is CancellationError ? "Import cancelled" : String(describing: error)
                self.finish(source.id)
                #if DEBUG
                print("[STEP] \(source.name): \(self.errors[source.id] ?? "failed")")
                #endif
            }
        }
    }

    /// The import numbers and diagnostics that used to sit in the STEP panel's "Details":
    /// only useful when something looks wrong, so they go to the debugger console.
    private static func logImport(of source: STEPSourceReference, content: STEPViewerContent) {
        #if DEBUG
        var lines = ["[STEP] \(source.name)"]
        lines.append("  \(content.infos.count) bod\(content.infos.count == 1 ? "y" : "ies") · "
                     + "\(content.edgeCount) edges shown · \(content.skippedEdgeCount) skipped")
        for info in content.infos {
            guard let size = content.size(of: info.id) else {
                continue
            }
            lines.append(String(format: "  Body %d: %g × %g × %g mm", info.number, size.x, size.y, size.z)
                         + (info.label.map { " (\($0))" } ?? ""))
        }
        let surfaces = content.surfaces
        lines.append("  \(surfaces.tessellatedFaceCount) of \(surfaces.reachableFaceCount) faces · \(surfaces.triangleCount) triangles"
                     + (surfaces.failedFaceCount > 0 ? " · \(surfaces.failedFaceCount) faces failed" : ""))
        for diagnostic in content.diagnostics {
            lines.append("  " + (diagnostic.entityID.map { "#\($0): " } ?? "") + diagnostic.message)
        }
        print(lines.joined(separator: "\n"))
        #endif
    }

    private func finish(_ id: UUID) {
        loadingIDs.remove(id)
        tokens.removeValue(forKey: id)
        tasks.removeValue(forKey: id)
    }

    func reportFailure(_ source: STEPSourceReference, message: String) {
        tasks[source.id]?.cancel()
        finish(source.id)
        if !sources.contains(where: { $0.id == source.id }) {
            sources.append(source)
        }
        documents.removeValue(forKey: source.id)
        sceneObservers.removeValue(forKey: source.id)
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
        sceneObservers.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        sources.removeAll { $0.id == id }
        if let selected = selectedModelID, sourceID(ofModel: selected) == id {
            selectedModelID = nil
        }
        legacyOffsets.removeValue(forKey: id)
        legacyFaces.removeValue(forKey: id)
        bodyStates.removeValue(forKey: id)
        for (key, model) in modelIDs.filter({ $0.key.source == id }) {
            modelIDs.removeValue(forKey: key)
            modelKeys.removeValue(forKey: model)
        }
        if selectedModelID == id {
            selectedModelID = nil
        }
        if activeID == id {
            activeID = sources.last?.id
        }
    }

    func clear() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        tokens.removeAll()
        loadingIDs.removeAll()
        documents.removeAll()
        sceneObservers.removeAll()
        errors.removeAll()
        sources.removeAll()
        legacyOffsets.removeAll()
        legacyFaces.removeAll()
        bodyStates.removeAll()
        modelIDs.removeAll()
        modelKeys.removeAll()
        picking = nil
        selectedModelID = nil
        activeID = nil
    }

    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }
}
