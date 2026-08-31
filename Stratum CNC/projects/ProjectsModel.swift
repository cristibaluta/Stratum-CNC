//
//  ProjectModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import Observation

enum ProjectError: Error {
    case projectAlreadyExists
    case assetImportFailed
}

@MainActor
final class ProjectsModel: ObservableObject {

    @Published private(set) var projects: [ProjectData] = []
    @Published var activeProject: ProjectData?

    private let paths: ProjectPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        do {
            self.paths = try ProjectPaths()
        } catch {
            fatalError("Unable to initialize project storage: \(error)")
        }

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        loadProjects()
    }

    func directoryURL(for project: ProjectData) -> URL {
        paths.directory(for: project)
    }

    // MARK: - Loading

    func loadProjects() {
        guard FileManager.default.fileExists(atPath: paths.projectsIndexFile.path) else {
            projects = []
            return
        }

        do {
            let data = try Data(contentsOf: paths.projectsIndexFile)
            projects = try decoder.decode([ProjectData].self, from: data)

            projects.sort {
                $0.modifiedAt > $1.modifiedAt
            }
        } catch {
            print("Failed to load projects: \(error)")
            projects = []
        }
    }

    // MARK: - Creation

    @discardableResult
    func createProject(name: String) throws -> ProjectData {
        // Create project data
        let stock = StockMaterial(name: "Aluminum", material: .aluminum, geometry: .rectangular(width: 150, height: 25, depth: 5))
        let project = ProjectData(name: name, stock: stock, isStockVisible: true, assets: nil)

        // Check if project already exist
        guard projects.first(where: { $0.name.lowercased() == name.lowercased() }) == nil else {
            throw ProjectError.projectAlreadyExists
        }

        // Create supporting files
        try FileManager.default.createDirectory(at: paths.directory(for: project), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.assetsDirectory(for: project), withIntermediateDirectories: true)

        try saveProjectMetadata(project)

        projects.insert(project, at: 0)

        try saveIndex()

        return project
    }

    // MARK: - Updating

    func update(_ project: ProjectData) throws {
        var updatedProject = project
        updatedProject.modifiedAt = .now

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updatedProject
        }

        try saveProjectMetadata(updatedProject)
        try saveIndex()
    }

    func importAsset(from url: URL) throws -> AssetData {
        guard var activeProject else {
            throw ProjectError.assetImportFailed
        }
        // 1. Move asset from original location to assets folder in the project
        guard url.startAccessingSecurityScopedResource() else {
            print("Could not access:", url)
            throw ProjectError.assetImportFailed
        }
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        let assetDestination = paths.assetsDirectory(for: activeProject).appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: assetDestination.path) {
            try? FileManager.default.removeItem(at: assetDestination)
        }
        try? FileManager.default.copyItem(at: url, to: assetDestination)

        // 2. Add asset to json
        var assets = activeProject.assets ?? []
        let asset = AssetData(name: url.lastPathComponent)
        assets.append(asset)
        activeProject.assets = assets
        try saveProjectMetadata(activeProject)

        return asset
    }

    // MARK: - Delete

    func delete(_ project: ProjectData) throws {
        let directory = paths.directory(for: project)

        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }

        projects.removeAll {
            $0.id == project.id
        }

        try saveIndex()
    }

    // MARK: - Preview

    func previewURL(for project: ProjectData) -> URL {
        paths.preview(for: project)
    }

    // MARK: - Persistence

    private func saveProjectMetadata(_ project: ProjectData) throws {
        let data = try encoder.encode(project)
        try data.write(to: paths.projectMetadata(for: project), options: .atomic)
    }

    private func saveIndex() throws {
        let data = try encoder.encode(projects)
        try data.write(to: paths.projectsIndexFile, options: .atomic)
    }
}
