//
//  ProjectModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 01/09/2026.
//

/*
 ┌─────────────────────────────────────────────────────┐
 │              ProjectModel (Single Source)           │
 │  ✓ Owns ProjectData (persisted)                     │
 │  ✓ Loads/saves to disk                              │
 │  ✓ Triggers auto-save on ProjectData changes        │
 └────────────────────┬────────────────────────────────┘
                      │
      ┌───────────────┼───────────────┐
      ↓               ↓               ↓
   CAMModel      ControllerModel  GCodeStore
   (Temporary)   (Temporary)      (Temporary)


ProjectModel (owns ProjectData)
    │
    ├─→ Load phase:
    │   CAMModel.stocks = projectData.stocks (the project's stocks, with their fixtures)
    │   CAMModel.setups = projectData.setups (each points at one of the stocks by id)
    │   CAMModel.canvasState = parse assets from projectData.assets
    │   CAMModel.toolpaths = load from toolpaths.json, each tool looked up by id in tools.json
    │
    ├─→ Edit phase:
    │   User edits in CAMView subviews
    │   Changes flow to CAMModel published properties
    │   CAMModel notifies ProjectModel via callbacks
    │
    └─→ Save phase:
        ProjectModel updates ProjectData
        ProjectModel saves to disk
*/

import SwiftUI
import Combine

enum ActiveTab: String, CaseIterable, Identifiable {
    case cam = "CAM"
    case controller = "Controller"

    var id: String {
        rawValue
    }
}

/// How the project was opened. Only `.project` has a CAM side; the other two
/// are Controller-only sessions started from the Projects page.
enum SessionKind {
    /// A saved project, or the "Try Without Project" scratch project.
    case project
    /// "Open Controller" from the Projects page.
    case controllerOnly
    /// "Import G-code" from the Projects page: the Controller showing one file.
    case gcodeFile
}

@MainActor
class ProjectModel: ObservableObject {

    /// Set by `ProjectsStore` right after creation, before the view appears.
    var sessionKind: SessionKind = .project

    /// Controller-only sessions have no CAM: its tab and CAM actions are hidden.
    var hidesCAM: Bool {
        sessionKind != .project
    }

    @Published var activeTab: ActiveTab = .cam

    @Published var project: Project
    @Published var projectData: ProjectData {
        didSet {
            hasUnsavedChanges = true
        }
    }
    @Published var toolpaths: [ToolpathData]?

    /// True from an edit until the debounced save has written it to disk.
    @Published private(set) var hasUnsavedChanges = false
    /// When the project was last written to disk; `nil` if it never was.
    @Published private(set) var lastSavedAt: Date?
    /// Why the last save failed; `nil` after a save that worked. Shown in the subtitle.
    @Published private(set) var saveError: String?
    /// Set when `project.json`, `tools.json` or `toolpaths.json` exists but couldn't be read. Saving that
    /// file is then off, so the unreadable one is never overwritten. Shown in the subtitle.
    @Published private(set) var loadProblem: String?
    private var projectFileUnreadable = false
    private var toolsFileUnreadable = false
    private var toolpathsFileUnreadable = false

    /// What `tools.json` holds on disk. The project keeps its own copy of every tool it uses, so
    /// it opens the same on a computer whose tool library has other tools or other ids. A tool
    /// joins it as soon as a toolpath uses it (see `saveToolsIfNew`).
    private var storedTools: [Tool] = []

    /// `tools.json`, next to `toolpaths.json`.
    private var toolsFile: URL {
        paths.toolpathsFile.deletingLastPathComponent().appendingPathComponent("tools.json")
    }

    /// What the subtitle shows instead of the save date, when something is wrong with the files.
    var storageProblem: String? {
        if let loadProblem {
            return loadProblem
        }
        if let saveError {
            return "Not saved: \(saveError)"
        }
        return nil
    }
    let paths: ProjectPaths

    @Published var camModel: CAMModel
    @Published var controllerModel = ControllerModel()

    @Published var gCodeStore = GCodeStore()

    /// The Toolpaths panel's "send to controller" mode: rows show checkboxes, and the program
    /// is built from the checked ones. Kept here, not in the panel, so it lives as long as the
    /// project is open and is never written to the project file.
    @Published var isChoosingToolpathsToSend = false
    /// The toolpaths the user unticked. Stored the other way round so that every toolpath is
    /// ticked by default, new ones included.
    @Published var uncheckedToolpathIDs: Set<UUID> = []
    @Published var joystickStore = GameControllerStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Starts / ends security-scoped access to the project folder. An external
    /// project's folder can only be written while its bookmark is active, so
    /// every write below goes through `withFolderAccess`. Internal and scratch
    /// projects use the defaults, which always succeed.
    private let beginFolderAccess: @MainActor () -> Bool
    private let endFolderAccess: @MainActor () -> Void

    // Rapid-fire edits (dragging an object, nudging it, live-typing in the inspector) only mark
    // the project as having unsaved changes. They reach the disk on a timer (`autosaveInterval`),
    // on the key actions of the toolpath panel (`saveIfNeeded`), and when the project closes.
    private static let autosaveInterval: TimeInterval = 30
    private var cancellables = Set<AnyCancellable>()
    private var loadedAssetNames = Set<String>()

    init(project: Project,
         paths: ProjectPaths,
         beginFolderAccess: @escaping @MainActor () -> Bool = { true },
         endFolderAccess: @escaping @MainActor () -> Void = {}) {
        self.project = project
        self.paths = paths
        self.beginFolderAccess = beginFolderAccess
        self.endFolderAccess = endFolderAccess

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        var projectData: ProjectData
        // Set when project.json exists but can't be used. The project then opens empty, and
        // nothing is written over the file (see `markUnreadable`).
        var unreadableMetadata: Error?

        do {
            let data = try Data(contentsOf: paths.projectMetadata)
            projectData = try decoder.decode(ProjectData.self, from: data)
            if let version = projectData.schemaVersion, version > ProjectData.currentSchemaVersion {
                throw ProjectError.newerFileVersion
            }
        } catch {
            print("Failed to load projects: \(error)")
            projectData = ProjectData(assets: nil)
            // A missing file is a new project, not a failure.
            if FileManager.default.fileExists(atPath: paths.projectMetadata.path) {
                unreadableMetadata = error
            }
        }
        // The folder identifies itself: keep the project's id and name in
        // project.json in step with the index (older files have a random id).
        projectData.id = project.id
        projectData.name = project.name
        self.projectData = projectData

        // The stocks are a list of the project, shared by its setups, and the fixtures hang on them.
        // A project saved before that (each setup carried its own stock, the alignment pins were
        // objects) is converted here; `projectData.stock` only seeds the list of one that had none.
        let migrated = ProjectStocks.migrate(setups: projectData.setups ?? [],
                                             stocks: projectData.stocks ?? [],
                                             legacyStock: projectData.legacyStock,
                                             legacyPins: projectData.alignmentPins ?? [])
        camModel = CAMModel(toolpaths: [],
                            setups: migrated.setups,
                            stocks: migrated.stocks,
                            groups: projectData.objectGroups ?? [],
                            newStock: projectData.legacyStock ?? .defaultWorkpiece)

        if let unreadableMetadata {
            markUnreadable(paths.projectMetadata, error: unreadableMetadata)
        }
        loadProjectData()

        // Restore the Controller's XY offset, then keep project.json in step
        // with it. Restored before subscribing, so loading doesn't count as
        // an edit; `dropFirst` skips the value `$xyOffset` replays on subscribe.
        controllerModel.scene.xyOffset = projectData.xyOffset ?? .zero
        controllerModel.scene.$xyOffset
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] offset in
                guard let self, self.projectData.xyOffset != offset else {
                    return
                }
                self.projectData.xyOffset = offset
            }
            .store(in: &cancellables)

        // Faces added, renamed, turned, reordered or deleted. Wired after the load, which
        // restores the saved ones through the initializer, so opening is not an edit.
        camModel.onSetupsChanged = { [weak self] setups in
            self?.projectData.setups = setups
        }

        // Groups created, renamed, changed or dissolved
        camModel.onGroupsChanged = { [weak self] groups in
            self?.projectData.objectGroups = groups
        }

        // Stocks added, edited or removed, and their fixtures
        camModel.onStocksChanged = { [weak self] stocks in
            self?.projectData.stocks = stocks
        }

        camModel.onToolpathsChanged = { [weak self] toolpaths in
            self?.toolpaths = toolpaths
            self?.hasUnsavedChanges = true
            self?.saveToolsIfNew()
        }

        // Wired up only after the initial load/restore above has finished:
        // loadProjectData() itself calls camModel.loadAndParseFileAt for
        // every saved asset, which would otherwise fire this callback with
        // each object's just-created *default* transform and immediately
        // persist that over the real saved one, before restoreTransform has
        // a chance to apply it.
        camModel.onObjectsChanged = { [weak self] objects in
            self?.updateAssetTransforms(from: objects)
        }

        // A STEP body was moved, turned, scaled or deleted: remember it, like an object's transform.
        camModel.stepWorkspace.onBodyStateChanged = { [weak self] id, key, state in
            guard let self,
                  let index = self.projectData.assets?.firstIndex(where: { $0.stepImportID == id }) else {
                return
            }
            var states = self.projectData.assets?[index].stepBodies ?? [:]
            states[key] = state
            self.projectData.assets?[index].stepBodies = states
            self.hasUnsavedChanges = true
        }

        Timer.publish(every: Self.autosaveInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.saveIfNeeded()
            }
            .store(in: &cancellables)

        // Upgrade legacy assets before a new toolpath can reference their IDs.
        updateAssetTransforms(from: camModel.canvasState.objects)

        // A project converted to stocks as a list is written in the new shape by the next save.
        // `alignmentPins` is only what an older project had: its pins are fixtures of the stocks now.
        if migrated.didMigrate, !projectFileUnreadable {
            projectData.setups = camModel.setups
            projectData.stocks = camModel.stocks
            projectData.alignmentPins = nil
        }

        // What the subtitle shows until something is saved in this session: the file's own date.
        lastSavedAt = (try? FileManager.default.attributesOfItem(atPath: paths.projectMetadata.path))?[.modificationDate] as? Date
        hasUnsavedChanges = migrated.didMigrate && !projectFileUnreadable
    }

    func loadProjectData() {
        // 1. Load assets and import into CAM, then restore each object's
        // saved position/scale/rotation on top of the freshly-parsed one.
        for asset in projectData.assets ?? [] {
            let url = paths.assetsDirectory.appendingPathComponent(asset.name)
            if Self.isSTEPAsset(asset.name) {
                do {
                    try loadSTEPAsset(asset)
                }
                catch {
                    let id = projectData.assets?.first(where: { $0.name == asset.name })?.stepImportID ?? asset.stepImportID ?? UUID()
                    camModel.stepWorkspace.reportFailure(
                        STEPSourceReference(id: id, name: asset.name, url: url),
                        message: String(describing: error))
                }
                continue
            }
            if let object = camModel.loadAndParseFileAt(url, restoring: asset.objects) {
                loadedAssetNames.insert(asset.name)
                if asset.objects == nil, let transform = asset.transform {
                    camModel.canvasState.restoreTransform(transform, objectID: object.id)
                }
            }
        }

        // The fixtures (alignment pins) are not loaded here: they are part of the stocks, and
        // `CAMModel` builds their objects from them.

        // 2. Load the project's tools; the toolpaths below only know them by id
        let toolsUrl = toolsFile
        do {
            let data = try Data(contentsOf: toolsUrl)
            storedTools = try decoder.decode([Tool].self, from: data)
        } catch {
            print("Failed to load tools: \(error)")
            storedTools = []
            if FileManager.default.fileExists(atPath: toolsUrl.path) {
                markUnreadable(toolsUrl, error: error)
            }
        }
        decoder.userInfo[.projectTools] = Dictionary(storedTools.map { ($0.id, $0) },
                                                     uniquingKeysWith: { first, _ in first })

        // 3. Load toolpaths and display in CAM
        let toolpaths: [ToolpathData]
        let toolpathsUrl = paths.toolpathsFile
        do {
            let data = try Data(contentsOf: toolpathsUrl)
            toolpaths = try decoder.decode([ToolpathData].self, from: data)
        } catch {
            print("Failed to load toolpaths: \(error)")
            toolpaths = []
            if FileManager.default.fileExists(atPath: toolpathsUrl.path) {
                markUnreadable(toolpathsUrl, error: error)
            }
        }
        self.toolpaths = toolpaths
        camModel.toolpaths = toolpaths

        // Only the active setup's objects are shown, and it is the first object's first setup
        camModel.ensureDefaultSetups()
        if let first = camModel.regularObjectIDs.first {
            camModel.focusObject(first, keepingActiveSetup: false)
        }
    }

    /// A file that exists couldn't be read. Keeps a copy, turns saving that file off (it would be
    /// replaced by the empty data the project opened with) and says so in the subtitle.
    private func markUnreadable(_ url: URL, error: Error) {
        let name = url.lastPathComponent
        if url == paths.projectMetadata {
            projectFileUnreadable = true
        } else if url == toolsFile {
            toolsFileUnreadable = true
        } else {
            toolpathsFileUnreadable = true
        }
        let backup = backUpUnreadableFile(at: url, beginAccess: beginFolderAccess, endAccess: endFolderAccess)
        let kept = backup.map { ", copy kept as \($0.lastPathComponent)" } ?? ""
        var what = "can't be read"
        if let projectError = error as? ProjectError, case .newerFileVersion = projectError {
            what = "was saved by a newer version of Stratum"
        }
        let message = "\(name) \(what)\(kept). Saving it is off."
        loadProblem = [loadProblem, message].compactMap { $0 }.joined(separator: " ")
    }

    func importAsset(from url: URL) throws -> AssetData {
        // Keep existing imports intact, even when a different source has the
        // same basename. A failed copy must not create a metadata entry.
        let fileManager = FileManager.default
        var assetDestination = paths.assetsDirectory.appendingPathComponent(url.lastPathComponent)
        var suffix = 2
        while fileManager.fileExists(atPath: assetDestination.path) {
            let stem = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
            assetDestination = paths.assetsDirectory.appendingPathComponent("\(stem) (\(suffix))\(ext)")
            suffix += 1
        }
        let destination = assetDestination
        try withFolderAccess {
            try fileManager.copyItem(at: url, to: destination)
        }

        // 2. Add asset to json
        var assets = projectData.assets ?? []
        let asset = AssetData(name: destination.lastPathComponent, transform: nil,
                              stepImportID: Self.isSTEPAsset(destination.lastPathComponent) ? UUID() : nil)
        assets.append(asset)
        projectData.assets = assets
        try saveProjectMetadata()

        return asset
    }

    static func isSTEPAsset(_ name: String) -> Bool {
        ["step", "stp"].contains(URL(fileURLWithPath: name).pathExtension.lowercased())
    }

    /// Source retention/reparse, not a serialized GPU mesh or D2_Object transform.
    /// Access must remain active until the asynchronous reader has finished.
    /// `generatePreview` is for a fresh import: once the model has loaded, its picture becomes the
    /// project's card preview. Reopening a project leaves the preview as it is.
    func loadSTEPAsset(_ asset: AssetData, generatePreview: Bool = false) throws {
        guard Self.isSTEPAsset(asset.name) else {
            return
        }
        let savedID = projectData.assets?.first(where: { $0.name == asset.name })?.stepImportID
        let id = savedID ?? asset.stepImportID ?? UUID()
        if savedID == nil,
           let index = projectData.assets?.firstIndex(where: { $0.name == asset.name }) {
            projectData.assets?[index].stepImportID = id
            try saveProjectMetadata()
        }
        guard beginFolderAccess() else {
            throw ProjectError.projectFolderMissing
        }
        let endAccess = endFolderAccess
        if let saved = projectData.assets?.first(where: { $0.name == asset.name })?.stepOffset ?? asset.stepOffset,
           saved.count == 3 {
            camModel.stepWorkspace.restoreLegacyOffset(SIMD3<Float>(Float(saved[0]), Float(saved[1]), Float(saved[2])), for: id)
        }
        if let face = projectData.assets?.first(where: { $0.name == asset.name })?.stepOrientation ?? asset.stepOrientation {
            camModel.stepWorkspace.restoreLegacyFace(face, for: id)
        }
        if let states = projectData.assets?.first(where: { $0.name == asset.name })?.stepBodies ?? asset.stepBodies {
            camModel.stepWorkspace.restoreBodyStates(states, for: id)
        }
        camModel.loadAndParseFileAt(paths.assetsDirectory.appendingPathComponent(asset.name), stepImportID: id,
                                   onSTEPFinished: { [weak self] in
            // Also called when the load failed or was cancelled, then there is no scene
            if generatePreview, let geometry = self?.camModel.stepWorkspace.documents[id]?.arrangedGeometry {
                self?.updatePreview(from: geometry)
            }
            endAccess()
        })
    }

    func reloadSTEPSource(_ id: UUID) throws {
        guard let asset = projectData.assets?.first(where: { $0.stepImportID == id }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        try loadSTEPAsset(asset)
    }

    /// Deletes a row of the objects list. A STEP file of several bodies loses just that body (saved as
    /// deleted, so it stays gone after a reload); deleting a file's last body removes the file.
    func removeSTEPModel(_ id: UUID) throws {
        let workspace = camModel.stepWorkspace
        guard let source = workspace.sourceID(ofModel: id) else {
            return
        }
        if workspace.body(ofModel: id) != nil, workspace.remainingBodies(inSource: source) > 1 {
            workspace.removeBody(model: id)
            return
        }
        try removeSTEPSource(source)
    }

    func removeSTEPSource(_ id: UUID) throws {
        let previous = projectData.assets
        projectData.assets?.removeAll { $0.stepImportID == id }
        do {
            try saveProjectMetadata()
        }
        catch {
            projectData.assets = previous
            throw error
        }
        // Leave the source copy on disk; only referenced assets reopen. Avoid
        // deleting data while an in-flight mapped reader is finishing cancellation.
        camModel.stepWorkspace.remove(id)
    }

    /// Draws the canvas objects into the project's `preview.png`, the picture on its card.
    /// Called right after an import has put the new object on the canvas.
    func updatePreview(from objects: [D2_Object], ignoringVisibility: Bool = false) {
        guard let data = ProjectPreviewRenderer.pngData(for: objects, ignoringVisibility: ignoringVisibility) else {
            return
        }
        writePreview(data)
    }

    /// Draws an imported STEP model (its edges, isometric) into `preview.png`. Called when the
    /// model has finished loading. Big models have many edges, so the drawing is off the main thread.
    func updatePreview(from geometry: STEPDisplayGeometry) {
        Task { [weak self] in
            let data = await Task.detached(priority: .utility) {
                ProjectPreviewRenderer.pngData(forSTEP: geometry)
            }.value
            guard let data else {
                return
            }
            self?.writePreview(data)
        }
    }

    private func writePreview(_ data: Data) {
        do {
            try withFolderAccess {
                try data.write(to: paths.preview, options: .atomic)
            }
        } catch {
            print("Failed to write preview: \(error)")
        }
    }

    /// Mirrors each live canvas object's position/scale/rotation back into
    /// `projectData.assets`, matched by file name (the same name both
    /// `AssetData` and `D2_Object` use). Called whenever the canvas reports
    /// an object was added, removed, moved, resized, or rotated, so the
    /// transform on disk always matches what's currently on screen.
    private func updateAssetTransforms(from objects: [D2_Object]) {
        // The fixtures aren't an asset file either: they are saved with the stocks (`projectData.stocks`)
        guard var assets = projectData.assets, !assets.isEmpty else {
            return
        }

        loadedAssetNames.formUnion(objects.compactMap(\.sourceAssetName))
        for index in assets.indices where loadedAssetNames.contains(assets[index].name) {
            assets[index].objects = objects.filter { $0.sourceAssetName == assets[index].name }.map { object in
                AssetObjectData(id: object.id, name: object.name,
                                transform: AssetTransform(x: object.position.x, y: object.position.y,
                                                          width: object.width, height: object.height,
                                                          rotation: object.rotationDegrees))
            }
        }
        projectData.assets = assets
    }

    /// Flush pending edits before closing or quitting; debounce alone can lose
    /// the final edit when this model is released before its timer fires.
    /// Writes the project if something changed since the last save. Called by the timer and by
    /// the key actions (Done, Preview, new toolpath).
    func saveIfNeeded() {
        guard hasUnsavedChanges else {
            return
        }
        try? save()
    }

    /// Writes the project. A failure is kept in `saveError` for the subtitle (autosave and the
    /// key actions ignore the thrown error), and cleared by the next save that works.
    func save() throws {
        do {
            try saveProjectMetadata()
            try saveToolpaths()
            hasUnsavedChanges = false
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            throw error
        }
    }

    private func saveProjectMetadata() throws {
        if projectFileUnreadable {
            throw ProjectError.fileUnreadable("project.json")
        }
        var stamped = projectData
        stamped.schemaVersion = ProjectData.currentSchemaVersion
        let data = try encoder.encode(stamped)
        try withFolderAccess {
            try data.write(to: paths.projectMetadata, options: .atomic)
        }
        lastSavedAt = Date()
    }

    /// Writes `tools.json`: the full data of every tool the toolpaths use. With `pruning` the tools
    /// nothing uses any more are dropped; without it the ones already in the file stay, because
    /// `toolpaths.json` on disk may still refer to them until the next full save.
    private func saveTools(pruning: Bool) throws {
        if toolsFileUnreadable {
            throw ProjectError.fileUnreadable("tools.json")
        }
        var tools: [Tool] = pruning ? [] : storedTools
        for tool in (toolpaths ?? []).map(\.tool) {
            if let index = tools.firstIndex(where: { $0.id == tool.id }) {
                tools[index] = tool
            } else {
                tools.append(tool)
            }
        }
        let data = try encoder.encode(tools)
        try withFolderAccess {
            try data.write(to: toolsFile, options: .atomic)
        }
        storedTools = tools
    }

    /// A tool that was just picked (or created for a rest toolpath) is written to `tools.json`
    /// right away, so the toolpath that uses it can always be opened again.
    private func saveToolsIfNew() {
        let known = Set(storedTools.map(\.id))
        guard (toolpaths ?? []).contains(where: { !known.contains($0.tool.id) }) else {
            return
        }
        try? saveTools(pruning: false)
    }

    private func saveToolpaths() throws {
        // Targets reference object IDs in project.json, and tools in tools.json, so persist those first.
        try saveProjectMetadata()
        // Before the tools are pruned: with an unreadable toolpaths file nothing counts as using them.
        if toolpathsFileUnreadable {
            throw ProjectError.fileUnreadable("toolpaths.json")
        }
        try saveTools(pruning: true)
        let data = try encoder.encode(toolpaths)
        try withFolderAccess {
            try data.write(to: paths.toolpathsFile, options: .atomic)
        }
        lastSavedAt = Date()
        hasUnsavedChanges = false
    }

    /// Runs `body` with the project folder's bookmark activated. Calls nest, so
    /// it's safe while the store is already holding access for the open project.
    private func withFolderAccess<T>(_ body: () throws -> T) throws -> T {
        guard beginFolderAccess() else {
            throw ProjectError.projectFolderMissing
        }
        defer {
            endFolderAccess()
        }
        return try body()
    }

    // MARK: CAM -> Controller

    /// "Preview in Controller": switches to the Controller and generates every toolpath that
    /// isn't ready, then builds the program from them, exactly as "Refresh from CAM" does there.
    /// The progress popover shows on the Controller's own button once it is on screen.
    ///
    /// `toolpaths` is what the program is built from (the user's picks, in list order); nil sends
    /// all of them.
    func previewInController(toolpaths: [ToolpathData]? = nil) {
        activeTab = .controller
        gCodeStore.generateGCode(using: camModel, toolpaths: toolpaths)
    }

}
