import Foundation
import Testing
@testable import Stratum_CNC

struct ProjectPersistenceTests {
    @Test @MainActor func scratchProjectSurvivesReopenWithoutChangingNamedUntitled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectsStore(documentsDirectory: root)
        let named = try store.createProject(name: "Untitled")
        store.open(named)
        let namedPaths = try #require(store.activeProjectModel?.paths)
        store.close()
        let original = try Data(contentsOf: namedPaths.projectMetadata)
        store.openZombieProject()
        let scratch = try #require(store.activeProjectModel)
        #expect(scratch.paths.projectDirectory != namedPaths.projectDirectory)
        scratch.projectData.isStockVisible = false
        scratch.camModel.addToolpath()
        store.close()
        store.openZombieProject()
        #expect(store.activeProjectModel?.projectData.isStockVisible == false)
        #expect(store.activeProjectModel?.camModel.toolpaths.count == 1)
        #expect(try Data(contentsOf: namedPaths.projectMetadata) == original)
        #expect(store.projects == [named])
        store.close()
    }

    @Test @MainActor func preservesShapeReferencesAndDeletedObjectsAcrossReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = Project(name: "Shape test")
        let paths = try ProjectPaths(project: project, documentsDirectory: root)
        try FileManager.default.createDirectory(at: paths.assetsDirectory, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("part.svg")
        try #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0 L10 0 L10 10 Z"/></svg>"#
            .write(to: source, atomically: true, encoding: .utf8)
        let model = ProjectModel(project: project, paths: paths)
        let asset = try model.importAsset(from: source)
        let object = try #require(model.camModel.loadAndParseFileAt(paths.assetsDirectory.appendingPathComponent(asset.name)))
        model.camModel.canvasState.moveObject(object.id, to: CGPoint(x: 20, y: 30))
        model.camModel.addToolpath()
        model.camModel.toolpaths[0].targets = [PathSelection(objectID: object.id, pathIndex: 0)]
        try model.save()
        let reopened = ProjectModel(project: project, paths: paths)
        let restored = try #require(reopened.camModel.canvasState.object(withID: object.id))
        #expect(restored.position == CGPoint(x: 20, y: 30))
        #expect(reopened.camModel.toolpaths[0].targets[0].objectID == restored.id)
        reopened.camModel.canvasState.removeObject(restored.id)
        try reopened.save()
        let afterDeletion = ProjectModel(project: project, paths: paths)
        #expect(afterDeletion.camModel.canvasState.objects.isEmpty)
    }

    @Test @MainActor func importsNeverOverwriteExistingAssetsOrHideCopyFailures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = Project(name: "Import test")
        let paths = try ProjectPaths(project: project, documentsDirectory: root)
        try FileManager.default.createDirectory(at: paths.assetsDirectory, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("part.svg")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        let model = ProjectModel(project: project, paths: paths)
        let first = try model.importAsset(from: source)
        try "replacement".write(to: source, atomically: true, encoding: .utf8)
        let second = try model.importAsset(from: source)
        #expect(first.name != second.name)
        #expect(try String(contentsOf: paths.assetsDirectory.appendingPathComponent(first.name), encoding: .utf8) == "original")
        #expect(throws: (any Error).self) { try model.importAsset(from: root.appendingPathComponent("missing.svg")) }
        #expect(model.projectData.assets?.count == 2)
    }

    @Test @MainActor func explicitSaveFlushesPendingMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = Project(name: "Metadata test")
        let paths = try ProjectPaths(project: project, documentsDirectory: root)
        try FileManager.default.createDirectory(at: paths.assetsDirectory, withIntermediateDirectories: true)
        let model = ProjectModel(project: project, paths: paths)
        model.projectData.isStockVisible = false
        try model.save()
        let reopened = ProjectModel(project: project, paths: paths)
        #expect(reopened.projectData.isStockVisible == false)
    }

    @Test @MainActor func restoresEditedToolpathsOnReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = Project(name: "Persistence test")
        let paths = try ProjectPaths(project: project, documentsDirectory: root)
        try FileManager.default.createDirectory(at: paths.assetsDirectory, withIntermediateDirectories: true)
        let model = ProjectModel(project: project, paths: paths)
        model.camModel.addToolpath()
        model.camModel.toolpaths[0].name = "Saved contour"
        let saved = model.camModel.toolpaths
        let reopened = ProjectModel(project: project, paths: paths)
        #expect(reopened.camModel.toolpaths == saved)
        model.camModel.deleteToolpath(saved[0].id)
        let afterDeletion = ProjectModel(project: project, paths: paths)
        #expect(afterDeletion.camModel.toolpaths.isEmpty)
    }
}
