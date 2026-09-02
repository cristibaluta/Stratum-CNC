//
//  ProjectsStore.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import Observation

enum ProjectError: Error {
    case projectNotFound
    case projectAlreadyExists
    case assetImportFailed
}

@MainActor
final class ProjectsStore: ObservableObject {

    @Published private(set) var projects: [Project] = []
    @Published var activeProject: Project?
    @Published var activeProjectModel: ProjectModel?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        loadProjects()
    }

    // MARK: - Loading

    func loadProjects() {
        guard FileManager.default.fileExists(atPath: ProjectPaths.projectsIndexFile.path) else {
            projects = []
            return
        }

        do {
            let data = try Data(contentsOf: ProjectPaths.projectsIndexFile)
            projects = try decoder.decode([Project].self, from: data)

            projects.sort {
                $0.modifiedAt > $1.modifiedAt
            }
        } catch {
            print("Failed to load projects: \(error)")
            projects = []
        }
    }

    func open(_ project: Project) {
        guard let paths = try? ProjectPaths(project: project) else {
            return
        }
        activeProject = project
        activeProjectModel = ProjectModel(project: project, paths: paths)
    }

    func openZombieProject() {
        // TODO: on second open, it does not load the previous data because project.json is recreated
        let project: Project = (try? createProject(name: "Untitled", isZombie: true)) ?? Project(name: "Untitled")
        guard let paths = try? ProjectPaths(project: project) else {
            return
        }
        activeProject = project
        activeProjectModel = ProjectModel(project: project, paths: paths)
    }

    func close() {
        // If project is unsaved, save it or ask if to save it
        activeProject = nil
        activeProjectModel = nil
    }

    // MARK: - Creation

    @discardableResult
    func createProject(name: String, isZombie: Bool = false) throws -> Project {

        // Check if project already exist
        guard projects.first(where: { $0.name.lowercased() == name.lowercased() }) == nil else {
            throw ProjectError.projectAlreadyExists
        }

        let project = Project(name: name)

        guard let paths = try? ProjectPaths(project: project) else {
            throw ProjectError.projectNotFound
        }

        let lastUsedGeometry = StockGeometry.rectangular(width: 150, height: 25, depth: 5)
        let lastStockVisibility = true
        let lastStockUsed = StockMaterial(name: "Aluminum", material: .aluminum, geometry: lastUsedGeometry)
        let projectData = ProjectData(stock: lastStockUsed, isStockVisible: lastStockVisibility, assets: nil)

        // Create supporting directories and files
        try FileManager.default.createDirectory(at: paths.projectDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.assetsDirectory, withIntermediateDirectories: true)
        try saveProjectMetadata(projectData, in: project)

        guard !isZombie else {
            return project
        }

        projects.insert(project, at: 0)
        try saveIndex()

        return project
    }

    // MARK: - Updating

    func update(_ project: Project) throws {
        var updatedProject = project
        updatedProject.modifiedAt = .now

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updatedProject
        }

        try saveIndex()
    }

    // MARK: - Delete

    func delete(_ project: Project) throws {
        guard let paths = try? ProjectPaths(project: project) else {
            return
        }
        let directory = paths.projectDirectory

        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }

        projects.removeAll {
            $0.id == project.id
        }

        try saveIndex()
    }

    // MARK: - Preview

    func previewURL(for project: Project) -> URL {
        guard let paths = try? ProjectPaths(project: project) else {
            return URL(fileURLWithPath: "")
        }
        return paths.preview
    }

    // MARK: - Persistence

    private func saveProjectMetadata(_ projectData: ProjectData, in project: Project) throws {
        guard let paths = try? ProjectPaths(project: project) else {
            return
        }
        let data = try encoder.encode(projectData)
        try data.write(to: paths.projectMetadata, options: .atomic)
    }

    private func saveIndex() throws {
        let data = try encoder.encode(projects)
        try data.write(to: ProjectPaths.projectsIndexFile, options: .atomic)
    }
}
