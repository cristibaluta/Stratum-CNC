import Foundation
import Testing
@testable import Stratum_CNC

struct ToolsStoreRegressionTests {
    @Test @MainActor func mergesDuplicateToolsAndPresetsWithinOneImport() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let library = ToolLibrary(schemaVersion: 1, source: ToolLibrarySource(
            name: "Test", url: "", retrieved: "", units: ToolLibraryUnits(
                diameter: "mm", length: "mm", feedRate: "mm/min", plungeFeedRate: "mm/min",
                depthOfCut: "mm", spindleRPM: "rpm")), tools: [])
        try JSONEncoder().encode(library).write(to: url)
        let store = ToolsStore(toolsFileURL: url)
        let first = ToolPreset(name: "Aluminum")
        let second = ToolPreset(name: "Wood")
        var tool = Tool(name: "Mill", shankDiameter: 3, toolDiameter: 3, length: 10,
                        type: .endMill, presets: [first, first])
        var repeated = tool
        repeated.presets = [first, second, second]
        let result = try store.importTools([tool, repeated])
        #expect(result.added == 1)
        #expect(result.updated == 1)
        #expect(store.tools.count == 1)
        #expect(store.tools.first?.presets == [first, second])
        try store.load()
        #expect(store.tools.count == 1)
        #expect(store.tools.first?.presets == [first, second])
        tool.presets = [second]
        #expect(try store.importTools([tool]).skipped == 1)
    }
}
