import Foundation
import Testing
@testable import Stratum_CNC

struct ProjectPathsRegressionTests {
    @Test(arguments: ["..", ".", "../outside", "part/nested", "", " ", "part\\nested"])
    func rejectsNamesThatAreNotSingleDirectories(name: String) {
        #expect(throws: ProjectPaths.PathError.self) {
            try ProjectPaths(project: Project(name: name))
        }
    }

    @Test func preservesOrdinaryNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try ProjectPaths(project: Project(name: "My part 1"), documentsDirectory: root)
        #expect(paths.projectDirectory.lastPathComponent == "My part 1")
        #expect(paths.projectDirectory.deletingLastPathComponent() == paths.projectsRoot)
    }
}
