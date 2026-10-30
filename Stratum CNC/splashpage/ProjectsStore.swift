//
//  ProjectsStore.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import AppKit
import Observation
import Combine

enum ProjectError: Error {
    case projectNotFound
    case projectAlreadyExists
    case assetImportFailed
    case notAProjectFolder
    /// An external project's folder can't be reached: deleted, moved, or on a drive that isn't mounted.
    case projectFolderMissing
    case bookmarkFailed
}

/// The bits of `project.json` needed to recognise a folder.
private struct ProjectIdentity: Decodable {
    let id: UUID
    let name: String?
}

@MainActor
final class ProjectsStore: ObservableObject {

    @Published private(set) var projects: [Project] = []
    @Published var activeProject: Project?
    @Published var activeProjectModel: ProjectModel?
    /// External projects whose folder couldn't be reached the last time
    /// bookmarks were resolved. They stay in the list.
    @Published private(set) var missingProjectIDs: Set<UUID> = []

    /// Resolved folder of each reachable external project.
    private var resolvedDirectories: [UUID: URL] = [:]
    /// How many times security-scoped access is currently held per project,
    /// so overlapping users (open project + grid thumbnail) don't release
    /// each other's access.
    private var accessCounts: [UUID: Int] = [:]
    /// The project whose access `open` is holding until it closes.
    private var accessedActiveProject: Project?

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
        resolveBookmarks()
    }

    // MARK: - Bookmarks and access

    func isMissing(_ project: Project) -> Bool {
        missingProjectIDs.contains(project.id)
    }

    /// Resolves every external project's bookmark. Stale bookmarks are
    /// re-created and the index rewritten; a folder that can't be reached
    /// (deleted, moved to the Trash, unmounted drive) is flagged as missing
    /// instead of being dropped from the list.
    func resolveBookmarks() {
        var indexChanged = false
        for index in projects.indices where projects[index].isExternal {
            if resolveBookmark(at: index) { indexChanged = true }
        }
        if indexChanged {
            do { try saveIndex() } catch { print("Failed to save refreshed bookmarks: \(error)") }
        }
    }

    /// Returns `true` when the project's bookmark data was refreshed and the
    /// index needs saving.
    private func resolveBookmark(at index: Int) -> Bool {
        let id = projects[index].id
        guard let data = projects[index].bookmark else { return false }

        resolvedDirectories[id] = nil
        missingProjectIDs.insert(id)

        guard let resolved = try? ProjectBookmark.resolve(data) else { return false }
        let url = resolved.url
        guard !url.path.contains("/.Trash/"),
              url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path) else {
            return false
        }

        resolvedDirectories[id] = url
        missingProjectIDs.remove(id)

        var changed = false
        // The folder was moved or renamed: the bookmark followed it.
        if projects[index].path != url.path {
            projects[index].path = url.path
            changed = true
        }
        // Stale: still resolves, but must be re-created while access is held.
        // If that fails the old data is kept; it still works for now.
        if resolved.isStale, let fresh = try? ProjectBookmark.make(for: url) {
            projects[index].bookmark = fresh
            changed = true
        }
        return changed
    }

    /// The project's folder, or `nil` for an external project that is missing.
    /// External folders are only readable while access is held; see
    /// `beginAccess` and `withAccess`.
    func directory(for project: Project) -> URL? {
        try? paths(for: project).projectDirectory
    }

    func paths(for project: Project) throws -> ProjectPaths {
        if project.isExternal {
            guard let directory = resolvedDirectories[project.id] else {
                throw ProjectError.projectFolderMissing
            }
            return ProjectPaths(projectDirectory: directory)
        }
        return try ProjectPaths(project: project, documentsDirectory: documentsDirectory)
    }

    /// Starts security-scoped access to an external project's folder. Every
    /// successful call must be paired with `endAccess`. Always succeeds for
    /// internal projects.
    @discardableResult
    func beginAccess(_ project: Project) -> Bool {
        guard project.isExternal else { return true }
        guard let url = resolvedDirectories[project.id] else { return false }
        let count = accessCounts[project.id, default: 0]
        if count == 0, !url.startAccessingSecurityScopedResource() { return false }
        accessCounts[project.id] = count + 1
        return true
    }

    func endAccess(_ project: Project) {
        guard project.isExternal, let count = accessCounts[project.id] else { return }
        if count <= 1 {
            accessCounts[project.id] = nil
            resolvedDirectories[project.id]?.stopAccessingSecurityScopedResource()
        } else {
            accessCounts[project.id] = count - 1
        }
    }

    /// Runs `body` with access to the project's folder; `nil` if it can't be reached.
    func withAccess<T>(to project: Project, _ body: (ProjectPaths) throws -> T) rethrows -> T? {
        guard beginAccess(project) else { return nil }
        defer { endAccess(project) }
        guard let paths = try? self.paths(for: project) else { return nil }
        return try body(paths)
    }

    private func releaseActiveAccess() {
        if let accessed = accessedActiveProject {
            endAccess(accessed)
            accessedActiveProject = nil
        }
    }

    func open(_ project: Project) {
        guard saveActiveProject() else { return }
        guard !isMissing(project), beginAccess(project) else {
            print("Project folder is not reachable: \(project.name)")
            return
        }
        guard let paths = try? self.paths(for: project) else {
            endAccess(project)
            return
        }
        // Access stays open until the project closes (or another replaces it).
        releaseActiveAccess()
        accessedActiveProject = project
        activeProject = project
        activeProjectModel = ProjectModel(project: project,
                                          paths: paths,
                                          beginFolderAccess: { [weak self] in self?.beginAccess(project) ?? false },
                                          endFolderAccess: { [weak self] in self?.endAccess(project) })
    }

    /// Opens the scratch project. `tab` picks which screen it starts on, and
    /// `gcodeURL` loads that G-code into the Controller first (it implies the
    /// Controller tab).
    func openZombieProject(tab: ActiveTab = .cam, gcodeURL: URL? = nil) {
        guard saveActiveProject() else { return }
        releaseActiveAccess()
        do {
            let project = try createProject(name: "Untitled", isZombie: true)
            let paths = try ProjectPaths(project: project, documentsDirectory: scratchDirectory)
            activeProject = project
            let model = ProjectModel(project: project, paths: paths)
            model.activeTab = gcodeURL == nil ? tab : .controller
            if gcodeURL != nil {
                model.sessionKind = .gcodeFile
            } else if tab == .controller {
                model.sessionKind = .controllerOnly
            }
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
        releaseActiveAccess()
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

    /// Creates a project. With `parentFolder` (a folder the user picked) the
    /// project is created as `<parentFolder>/<name>/` and tracked by a
    /// security-scoped bookmark; without it, it lives inside Stratum.
    @discardableResult
    func createProject(name: String, in parentFolder: URL? = nil, isZombie: Bool = false) throws -> Project {

        if let parentFolder, !isZombie {
            return try createExternalProject(name: name, in: parentFolder)
        }

        // Internal projects are folders named after the project, so two of
        // them can't share a name. External ones can: they sit in different folders.
        guard isZombie || projects.first(where: { !$0.isExternal && $0.name.lowercased() == name.lowercased() }) == nil else {
            throw ProjectError.projectAlreadyExists
        }

        let project = Project(id: UUID(),
                              name: name,
                              createdAt: .now,
                              modifiedAt: .now)

        let paths = try ProjectPaths(project: project, documentsDirectory: isZombie ? scratchDirectory : documentsDirectory)
        if isZombie {
            // TODO: what is this? we don't need legacy stuff
            // Preserve old unlisted scratch projects, but never adopt a saved project named Untitled.
            let legacy = try ProjectPaths(project: project, documentsDirectory: documentsDirectory)
            if !FileManager.default.fileExists(atPath: paths.projectDirectory.path),
               !projects.contains(where: { $0.name.lowercased() == name.lowercased() }),
               FileManager.default.fileExists(atPath: legacy.projectMetadata.path) {
                try FileManager.default.copyItem(at: legacy.projectDirectory, to: paths.projectDirectory)
            }
            if FileManager.default.fileExists(atPath: paths.projectMetadata.path) {
                return project
            }
        }

        try writeNewProjectFiles(for: project, at: paths)

        guard !isZombie else {
            return project
        }

        projects.insert(project, at: 0)
        try saveIndex()

        return project
    }

    private func createExternalProject(name: String, in parentFolder: URL) throws -> Project {

        guard ProjectPaths.isValidName(name) else {
            throw ProjectPaths.PathError.invalidProjectName
        }

        let didAccess = parentFolder.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                parentFolder.stopAccessingSecurityScopedResource()
            }
        }

        let folder = parentFolder.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw ProjectError.projectAlreadyExists
        }

        var project = Project(id: UUID(),
                              name: name,
                              createdAt: .now,
                              modifiedAt: .now)
        try writeNewProjectFiles(for: project, at: ProjectPaths(projectDirectory: folder))

        // The folder exists now, so the bookmark can be made (the parent's
        // access still covers it). If anything below fails, undo the folder.
        let bookmark: Data
        let resolvedURL: URL
        do {
            bookmark = try ProjectBookmark.make(for: folder)
            resolvedURL = try ProjectBookmark.resolve(bookmark).url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw ProjectError.bookmarkFailed
        }

        project.bookmark = bookmark
        project.path = resolvedURL.path
        resolvedDirectories[project.id] = resolvedURL
        projects.insert(project, at: 0)
        do {
            try saveIndex()
        } catch {
            projects.removeAll { $0.id == project.id }
            resolvedDirectories[project.id] = nil
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return project
    }

    /// Creates the project folder with its `assets` directory and a fresh `project.json`.
    private func writeNewProjectFiles(for project: Project, at paths: ProjectPaths) throws {
        let lastUsedGeometry = StockGeometry.rectangular(width: 100, height: 100, depth: 10)
        let lastStockVisibility = true
        let lastStockUsed = StockMaterial(name: "Aluminum",
                                          material: .aluminum,
                                          geometry: lastUsedGeometry)
        let projectData = ProjectData(id: project.id,
                                      name: project.name,
                                      stock: lastStockUsed,
                                      isStockVisible: lastStockVisibility,
                                      assets: nil)

        // Create supporting directories and files
        try FileManager.default.createDirectory(at: paths.projectDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.assetsDirectory, withIntermediateDirectories: true)
        try saveProjectMetadata(projectData, at: paths)
    }

    /// Registers a project folder from anywhere on disk (one that holds a
    /// `project.json`) in place: nothing is copied or written. The app keeps a
    /// security-scoped bookmark and the path in `projects.json`.
    ///
    /// A folder already in the list (same id, or same location) isn't added
    /// twice; the existing entry is returned, and if its folder had gone
    /// missing it is re-pointed at this one.
    @discardableResult
    func openProjectFolder(_ folder: URL) throws -> Project {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")) else {
            throw ProjectError.notAProjectFolder
        }
        // Folders saved before id and name were stamped carry only a random id.
        let identity = try? decoder.decode(ProjectIdentity.self, from: data)

        let standardized = folder.standardizedFileURL.path
        let existingIndex = projects.firstIndex { project in
            project.id == identity?.id
                || (project.isExternal && resolvedDirectories[project.id]?.standardizedFileURL.path == standardized)
        }

        let bookmark: Data
        do { bookmark = try ProjectBookmark.make(for: folder) } catch { throw ProjectError.bookmarkFailed }

        if let existingIndex {
            // Already listed. An external project whose folder couldn't be
            // reached, or one the user is picking again (the fresh pick carries
            // the app's current read-write scope, which an older read-only
            // bookmark lacks), gets its bookmark replaced. Skipped while access
            // is held, so begin/end calls stay paired on the same URL.
            if projects[existingIndex].isExternal, accessCounts[projects[existingIndex].id] == nil {
                projects[existingIndex].bookmark = bookmark
                projects[existingIndex].path = folder.path
                if let resolved = try? ProjectBookmark.resolve(bookmark) {
                    resolvedDirectories[projects[existingIndex].id] = resolved.url
                    missingProjectIDs.remove(projects[existingIndex].id)
                }
                try saveIndex()
            }
            return projects[existingIndex]
        }

        let candidate = identity?.name ?? folder.lastPathComponent
        let name = ProjectPaths.isValidName(candidate) ? candidate : folder.lastPathComponent
        guard ProjectPaths.isValidName(name) else {
            throw ProjectError.notAProjectFolder
        }

        let resolved = try ProjectBookmark.resolve(bookmark)
        let project = Project(id: identity?.id ?? UUID(),
                              name: name,
                              createdAt: .now,
                              modifiedAt: .now,
                              bookmark: bookmark,
                              path: resolved.url.path)
        resolvedDirectories[project.id] = resolved.url
        projects.insert(project, at: 0)
        do {
            try saveIndex()
        } catch {
            projects.removeAll { $0.id == project.id }
            resolvedDirectories[project.id] = nil
            throw error
        }
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

    /// Deletes an internal project's folder. An external project is only
    /// removed from the list: the user's folder is never touched.
    func delete(_ project: Project) throws {
        if project.isExternal {
            try removeFromList(project)
            return
        }
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

    /// Forgets a project without touching its folder.
    func removeFromList(_ project: Project) throws {
        if accessCounts[project.id] != nil {
            resolvedDirectories[project.id]?.stopAccessingSecurityScopedResource()
            accessCounts[project.id] = nil
        }
        resolvedDirectories[project.id] = nil
        missingProjectIDs.remove(project.id)
        projects.removeAll { $0.id == project.id }
        try saveIndex()
    }

    // MARK: - Preview

    /// The grid thumbnail. Read eagerly inside a short access window, since
    /// an external folder can't be read once access is released.
    func previewImage(for project: Project) -> NSImage? {
        withAccess(to: project) { paths in
            (try? Data(contentsOf: paths.preview)).flatMap { NSImage(data: $0) }
        } ?? nil
    }

    /// The stock's material and size ("Aluminum · 100 × 100 × 10 mm") for the card, read from the
    /// project's own file. Nil when the project has no stock or its file can't be read.
    func stockSummary(for project: Project) -> String? {
        struct StockOnly: Decodable {
            var stock: StockMaterial?
        }
        return withAccess(to: project) { paths in
            (try? Data(contentsOf: paths.projectMetadata))
                .flatMap { try? decoder.decode(StockOnly.self, from: $0) }?
                .stock?.cardSummary
        } ?? nil
    }

    /// The material of the project's stock, to tint the card's preview. Nil when there is no stock.
    func stockMaterialType(for project: Project) -> StockMaterialType? {
        struct StockOnly: Decodable {
            var stock: StockMaterial?
        }
        return withAccess(to: project) { paths in
            (try? Data(contentsOf: paths.projectMetadata))
                .flatMap { try? decoder.decode(StockOnly.self, from: $0) }?
                .stock?.material
        } ?? nil
    }

    func revealInFinder(_ project: Project) {
        guard let directory = directory(for: project) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
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
