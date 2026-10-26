//
//  ProjectsStore.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import Observation
import Combine

enum ProjectError: Error {
    case projectNotFound
    case projectAlreadyExists
    case assetImportFailed
    case notAProjectFolder
}

@MainActor
final class ProjectsStore: ObservableObject {

    @Published private(set) var projects: [Project] = []
    @Published var activeProject: Project?
    @Published var activeProjectModel: ProjectModel?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let documentsDirectory: URL
    private var indexFile: URL { documentsDirectory.appendingPathComponent("projects.json") }
    private var scratchDirectory: URL { documentsDirectory.appendingPathComponent(".stratum-scratch", isDirectory: true) }

    init(documentsDirectory: URL = ProjectPaths.appDocuments) {
        self.documentsDirectory = documentsDirectory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        loadProjects()
    }

    // MARK: - Loading

    func loadProjects() {
        guard FileManager.default.fileExists(atPath: indexFile.path) else {
            projects = []
            return
        }

        do {
            let data = try Data(contentsOf: indexFile)
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
        guard saveActiveProject() else { return }
        guard let paths = try? ProjectPaths(project: project, documentsDirectory: documentsDirectory) else {
            return
        }
        activeProject = project
        activeProjectModel = ProjectModel(project: project, paths: paths)
    }

    /// Opens the scratch project. `tab` picks which screen it starts on, and
    /// `gcodeURL` loads that G-code into the Controller first (it implies the
    /// Controller tab).
    func openZombieProject(tab: ActiveTab = .cam, gcodeURL: URL? = nil) {
        guard saveActiveProject() else { return }
        do {
            let project = try createProject(name: "Untitled", isZombie: true)
            let paths = try ProjectPaths(project: project, documentsDirectory: scratchDirectory)
            activeProject = project
            let model = ProjectModel(project: project, paths: paths)
            model.activeTab = gcodeURL == nil ? tab : .controller
            if let gcodeURL {
                // Same load and resets as the Controller's own G-code importer.
                // Access stays open: the load is asynchronous.
                _ = gcodeURL.startAccessingSecurityScopedResource()
                model.gCodeStore.document.load(from: gcodeURL)
                model.gCodeStore.selectedToolpathID = nil
                model.gCodeStore.requestedLine = nil
                model.gCodeStore.analyzedLineCount = -1
            }
            activeProject = project
            activeProjectModel = model
        } catch {
            print("Failed to open scratch project: \(error)")
        }
    }

    func close() {
        guard saveActiveProject() else { return }
        activeProject = nil
        activeProjectModel = nil
    }

    @discardableResult
    func saveActiveProject() -> Bool {
        do {
            try activeProjectModel?.save()
            return true
        } catch {
            print("Failed to save project: \(error)")
            return false
        }
    }

    // MARK: - Creation

    @discardableResult
    func createProject(name: String, isZombie: Bool = false) throws -> Project {

        // Check if project already exist
        guard isZombie || projects.first(where: { $0.name.lowercased() == name.lowercased() }) == nil else {
            throw ProjectError.projectAlreadyExists
        }

        let project = Project(name: name)

        let paths = try ProjectPaths(project: project, documentsDirectory: isZombie ? scratchDirectory : documentsDirectory)
        if isZombie {
            // Preserve old unlisted scratch projects, but never adopt a saved project named Untitled.
            let legacy = try ProjectPaths(project: project, documentsDirectory: documentsDirectory)
            if !FileManager.default.fileExists(atPath: paths.projectDirectory.path),
               !projects.contains(where: { $0.name.lowercased() == name.lowercased() }),
               FileManager.default.fileExists(atPath: legacy.projectMetadata.path) {
                try FileManager.default.copyItem(at: legacy.projectDirectory, to: paths.projectDirectory)
            }
            if FileManager.default.fileExists(atPath: paths.projectMetadata.path) { return project }
        }

        let lastUsedGeometry = StockGeometry.rectangular(width: 100, height: 100, depth: 10)
        let lastStockVisibility = true
        let lastStockUsed = StockMaterial(name: "Aluminum",
                                          material: .aluminum,
                                          geometry: lastUsedGeometry)
        let projectData = ProjectData(stock: lastStockUsed,
                                      isStockVisible: lastStockVisibility,
                                      assets: nil)

        // Create supporting directories and files
        try FileManager.default.createDirectory(at: paths.projectDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.assetsDirectory, withIntermediateDirectories: true)
        try saveProjectMetadata(projectData, at: paths)

        guard !isZombie else {
            return project
        }

        projects.insert(project, at: 0)
        try saveIndex()

        return project
    }

    /// Adds a project folder from anywhere on disk (one that holds a
    /// `project.json`) to the app's projects, by copying it into the projects
    /// folder, and returns it. The original is left untouched.
    @discardableResult
    func importProjectFolder(_ url: URL) throws -> Project {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path),
              ProjectPaths.isValidName(name) else {
            throw ProjectError.notAProjectFolder
        }
        guard !projects.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
            throw ProjectError.projectAlreadyExists
        }

        let project = Project(name: name)
        let paths = try ProjectPaths(project: project, documentsDirectory: documentsDirectory)
        guard !FileManager.default.fileExists(atPath: paths.projectDirectory.path) else {
            throw ProjectError.projectAlreadyExists
        }
        try FileManager.default.copyItem(at: url, to: paths.projectDirectory)

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
        guard let paths = try? ProjectPaths(project: project, documentsDirectory: documentsDirectory) else {
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
        guard let paths = try? ProjectPaths(project: project, documentsDirectory: documentsDirectory) else {
            return URL(fileURLWithPath: "")
        }
        return paths.preview
    }

    // MARK: - Persistence

    private func saveProjectMetadata(_ projectData: ProjectData, at paths: ProjectPaths) throws {
        let data = try encoder.encode(projectData)
        try data.write(to: paths.projectMetadata, options: .atomic)
    }

    private func saveIndex() throws {
        let data = try encoder.encode(projects)
        try data.write(to: indexFile, options: .atomic)
    }
}
