//
//  ProjectStore.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//


import Foundation
import Observation

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

        load()
    }

    func directoryURL(for project: ProjectData) -> URL {
        paths.directory(for: project)
    }

    // MARK: - Loading

    func load() {
        guard FileManager.default.fileExists(atPath: paths.indexFile.path) else {
            projects = []
            return
        }

        do {
            let data = try Data(contentsOf: paths.indexFile)
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
        let project = ProjectData(name: name, assets: [])

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
        try data.write(to: paths.indexFile, options: .atomic)
    }
}
