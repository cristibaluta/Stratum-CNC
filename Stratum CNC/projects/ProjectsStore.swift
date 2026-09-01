//
//  ProjectModel.swift
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

    let paths: ProjectPaths

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

    // MARK: - Loading

    func loadProjects() {
        guard FileManager.default.fileExists(atPath: paths.projectsIndexFile.path) else {
            projects = []
            return
        }

        do {
            let data = try Data(contentsOf: paths.projectsIndexFile)
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
        activeProject = project
        activeProjectModel = ProjectModel(project: project, paths: paths)
    }

    func openZombieProject() {
        let project = Project(name: "Untitled")
        activeProject = project
        activeProjectModel = ProjectModel(project: project, paths: paths)
    }

    // MARK: - Creation

    @discardableResult
    func createProject(name: String) throws -> (Project, ProjectData) {
        // Forget the previous project
        activeProject = nil
        activeProjectModel = nil

        let project = Project(name: name)
        // Create project data
        let stock = StockMaterial(name: "Aluminum", material: .aluminum, geometry: .rectangular(width: 150, height: 25, depth: 5))
        let projectData = ProjectData(stock: stock, isStockVisible: true, assets: nil)

        // Check if project already exist
        guard projects.first(where: { $0.name.lowercased() == name.lowercased() }) == nil else {
            throw ProjectError.projectAlreadyExists
        }

        // Create supporting files
        try FileManager.default.createDirectory(at: paths.projectDirectory(for: project), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.assetsDirectory(for: project), withIntermediateDirectories: true)

        try saveProjectMetadata(projectData, in: project)

        projects.insert(project, at: 0)

        try saveIndex()

        return (project, projectData)
    }

    // MARK: - Updating

//    func update(_ project: Project) throws {
//        var updatedProject = project
//        updatedProject.modifiedAt = .now
//
//        if let index = projects.firstIndex(where: { $0.id == project.id }) {
//            projects[index] = updatedProject
//        }
//
//        try saveProjectMetadata(updatedProject)
//        try saveIndex()
//    }

    // MARK: - Delete

    func delete(_ project: Project) throws {
        let directory = paths.projectDirectory(for: project)

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
        paths.preview(for: project)
    }

    // MARK: - Persistence

    private func saveProjectMetadata(_ projectData: ProjectData, in project: Project) throws {
        let data = try encoder.encode(projectData)
        try data.write(to: paths.projectMetadata(for: project), options: .atomic)
    }

    private func saveIndex() throws {
        let data = try encoder.encode(projects)
        try data.write(to: paths.projectsIndexFile, options: .atomic)
    }
}
