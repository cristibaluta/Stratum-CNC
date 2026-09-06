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

enum ActiveTab: String, CaseIterable, Identifiable {
    case cam = "CAM"
    case controller = "Controller"

    var id: String {
        rawValue
    }
}

@MainActor
class ProjectModel: ObservableObject {

    @Published var activeTab: ActiveTab = .cam

    @Published var project: Project
    @Published var projectData: ProjectData {
        didSet {
            print("project data changed to: \(projectData)")
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

    init(project: Project, paths: ProjectPaths) {
        self.project = project
        self.paths = paths

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let projectData: ProjectData

        do {
            let data = try Data(contentsOf: paths.projectMetadata)
            projectData = try decoder.decode(ProjectData.self, from: data)
        } catch {
            print("Failed to load projects: \(error)")
            projectData = ProjectData(stock: nil,
                                      isStockVisible: nil,
                                      assets: nil)
        }
        self.projectData = projectData

        let defaultStock = StockMaterial(
            name: "Workpiece",
            material: .aluminum,
            geometry: .rectangular(width: 100, height: 50, depth: 10)
        )

        camModel = CAMModel(selectedStockMaterial: projectData.stock ?? defaultStock,
                            toolpaths: [])

//        projectData.isStockVisible.publisher.sink { [weak self] newValue in
//            print("new isStockVisible \(newValue)")
//        }
        camModel.onStockChanged = { [weak self] stock in
            self?.projectData.stock = stock
            try? self?.saveProjectMetadata()
        }

        camModel.onToolpathsChanged = { [weak self] toolpaths in
            self?.toolpaths = toolpaths
            try? self?.saveToolpaths()
        }

        loadProjectData()
    }

    func loadProjectData() {
        // 1. Load material
        if let stock = projectData.stock {
            camModel.selectedStockMaterial = stock
        }

        // 2. Load assets and import into CAM
        for asset in projectData.assets ?? [] {
            let url = paths.assetsDirectory.appendingPathComponent(asset.name)
            camModel.loadAndParseFileAt(url)
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
    }

    func importAsset(from url: URL) throws -> AssetData {
        // 1. Move asset from original location to assets folder in the project
        let assetDestination = paths.assetsDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: assetDestination.path) {
            try? FileManager.default.removeItem(at: assetDestination)
        }
        try? FileManager.default.copyItem(at: url, to: assetDestination)

        // 2. Add asset to json
        var assets = projectData.assets ?? []
        let asset = AssetData(name: url.lastPathComponent, transform: nil)
        assets.append(asset)
        projectData.assets = assets
        try saveProjectMetadata()

        return asset
    }

    private func saveProjectMetadata() throws {
        let data = try encoder.encode(projectData)
        try data.write(to: paths.projectMetadata, options: .atomic)
    }

    private func saveToolpaths() throws {
        let data = try encoder.encode(toolpaths)
        try data.write(to: paths.toolpathsFile, options: .atomic)
    }

}
