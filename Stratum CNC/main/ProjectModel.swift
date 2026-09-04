//
//  ProjectModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 01/09/2026.
//

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

    @Published var camModel = CAMModel()
    @Published var controllerModel = ControllerModel()

    @Published var gCodeStore = GCodeStore()
    @Published var joystickStore = GameControllerStore()

    @Published var project: Project
    @Published var projectData: ProjectData {
        didSet {
            print("project data changed to: \(projectData)")
        }
    }
    let paths: ProjectPaths

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

        do {
            let data = try Data(contentsOf: paths.projectMetadata)
            let projectData = try decoder.decode(ProjectData.self, from: data)
            self.projectData = projectData
        } catch {
            print("Failed to load projects: \(error)")
            self.projectData = ProjectData(stock: nil, isStockVisible: nil, assets: nil)
        }

        projectData.isStockVisible.publisher.sink { [weak self] newValue in
            print("new isStockVisible \(newValue)")
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
        let toolpathsUrl = paths.toolpathsFile
        print(toolpathsUrl)
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
        try saveProjectMetadata(projectData, in: project)

        return asset
    }

    private func saveProjectMetadata(_ projectData: ProjectData, in project: Project) throws {
        let data = try encoder.encode(projectData)
        try data.write(to: paths.projectMetadata, options: .atomic)
    }

}
