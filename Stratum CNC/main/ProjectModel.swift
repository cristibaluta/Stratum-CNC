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
    │   CAMModel.selectedStockMaterial = projectData.stock
    │   CAMModel.canvasState = parse assets from projectData.assets
    │   CAMModel.toolpaths = load from projectData.toolpaths
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
    var hidesCAM: Bool { sessionKind != .project }

    @Published var activeTab: ActiveTab = .cam

    @Published var project: Project
    @Published var projectData: ProjectData {
        didSet {
            saveMetadataTrigger.send(())
        }
    }
    @Published var toolpaths: [ToolpathData]?
    let paths: ProjectPaths

    @Published var camModel: CAMModel
    @Published var controllerModel = ControllerModel()

    @Published var gCodeStore = GCodeStore()
    @Published var joystickStore = GameControllerStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Starts / ends security-scoped access to the project folder. An external
    /// project's folder can only be written while its bookmark is active, so
    /// every write below goes through `withFolderAccess`. Internal and scratch
    /// projects use the defaults, which always succeed.
    private let beginFolderAccess: @MainActor () -> Bool
    private let endFolderAccess: @MainActor () -> Void

    // Rapid-fire edits (dragging an object, nudging it, live-typing in the
    // inspector) each call through to here — writing to disk on every one
    // would mean dozens of writes per second. Every save request goes
    // through this subject instead of hitting disk directly; `debounce`
    // waits for a quiet gap before actually saving, so a burst of changes
    // collapses into a single write once the user pauses.
    private let saveMetadataTrigger = PassthroughSubject<Void, Never>()
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

        do {
            let data = try Data(contentsOf: paths.projectMetadata)
            projectData = try decoder.decode(ProjectData.self, from: data)
        } catch {
            print("Failed to load projects: \(error)")
            projectData = ProjectData(stock: nil,
                                      isStockVisible: nil,
                                      assets: nil)
        }
        // The folder identifies itself: keep the project's id and name in
        // project.json in step with the index (older files have a random id).
        projectData.id = project.id
        projectData.name = project.name
        self.projectData = projectData

        let defaultStock = StockMaterial(
            name: "Workpiece",
            material: .aluminum,
            geometry: .rectangular(width: 100, height: 100, depth: 10)
        )

        camModel = CAMModel(selectedStockMaterial: projectData.stock ?? defaultStock,
                            toolpaths: [])

//        projectData.isStockVisible.publisher.sink { [weak self] newValue in
//            print("new isStockVisible \(newValue)")
//        }
        camModel.onStockChanged = { [weak self] stock in
            self?.projectData.stock = stock
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
                guard let self, self.projectData.xyOffset != offset else { return }
                self.projectData.xyOffset = offset
            }
            .store(in: &cancellables)

        camModel.onToolpathsChanged = { [weak self] toolpaths in
            self?.toolpaths = toolpaths
            try? self?.saveToolpaths()
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

        saveMetadataTrigger
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                try? self?.saveProjectMetadata()
            }
            .store(in: &cancellables)

        // Upgrade legacy assets before a new toolpath can reference their IDs.
        updateAssetTransforms(from: camModel.canvasState.objects)
    }

    func loadProjectData() {
        // 1. Load material
        if let stock = projectData.stock {
            camModel.selectedStockMaterial = stock
        }

        // 2. Load assets and import into CAM, then restore each object's
        // saved position/scale/rotation on top of the freshly-parsed one.
        for asset in projectData.assets ?? [] {
            let url = paths.assetsDirectory.appendingPathComponent(asset.name)
            if let object = camModel.loadAndParseFileAt(url, restoring: asset.objects) {
                loadedAssetNames.insert(asset.name)
                if asset.objects == nil, let transform = asset.transform {
                    camModel.canvasState.restoreTransform(transform, objectID: object.id)
                }
            }
        }

        // 3. Load toolpaths and display in CAM
        let toolpaths: [ToolpathData]
        let toolpathsUrl = paths.toolpathsFile
        print(toolpathsUrl)
        do {
            let data = try Data(contentsOf: toolpathsUrl)
            toolpaths = try decoder.decode([ToolpathData].self, from: data)
        } catch {
            print("Failed to load toolpaths: \(error)")
            toolpaths = []
        }
        self.toolpaths = toolpaths
        camModel.toolpaths = toolpaths
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
        let asset = AssetData(name: destination.lastPathComponent, transform: nil)
        assets.append(asset)
        projectData.assets = assets
        try saveProjectMetadata()

        return asset
    }

    /// Mirrors each live canvas object's position/scale/rotation back into
    /// `projectData.assets`, matched by file name (the same name both
    /// `AssetData` and `D2_Object` use). Called whenever the canvas reports
    /// an object was added, removed, moved, resized, or rotated, so the
    /// transform on disk always matches what's currently on screen.
    private func updateAssetTransforms(from objects: [D2_Object]) {
        guard var assets = projectData.assets, !assets.isEmpty else { return }

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
    func save() throws {
        try saveProjectMetadata()
        try saveToolpaths()
    }

    private func saveProjectMetadata() throws {
        let data = try encoder.encode(projectData)
        try withFolderAccess {
            try data.write(to: paths.projectMetadata, options: .atomic)
        }
    }

    private func saveToolpaths() throws {
        // Targets reference object IDs in project.json, so persist those first.
        try saveProjectMetadata()
        let data = try encoder.encode(toolpaths)
        try withFolderAccess {
            try data.write(to: paths.toolpathsFile, options: .atomic)
        }
    }

    /// Runs `body` with the project folder's bookmark activated. Calls nest, so
    /// it's safe while the store is already holding access for the open project.
    private func withFolderAccess<T>(_ body: () throws -> T) throws -> T {
        guard beginFolderAccess() else { throw ProjectError.projectFolderMissing }
        defer { endFolderAccess() }
        return try body()
    }

}
