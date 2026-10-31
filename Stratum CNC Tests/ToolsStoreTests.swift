//
//  ToolsStoreTests.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 31.10.2026.
//


//
//  ToolsStoreTests.swift
//  Stratum CNC
//
//  Sources in the store: what add, duplicate and import do to them.
//  Adjust the @testable import if the module name differs.
//

import XCTest
@testable import Stratum_CNC

@MainActor
final class ToolsStoreTests: XCTestCase {

    private var directory: URL!
    private var fileURL: URL!

    private let bundledToolID = UUID()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolsStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("tools.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    /// A library with the two fixed sources and one bundled tool.
    private func makeStore() throws -> ToolsStore {
        let json = """
        { "schemaVersion": 2,
          "source": { "name": "Makera", "url": "", "retrieved": "2026-08-25",
            "units": { "diameter": "mm", "length": "mm", "feedRate": "mm/min",
                       "plungeFeedRate": "mm/min", "depthOfCut": "mm", "spindleRPM": "RPM" } },
          "sources": [
            { "id": "\(ToolSourceInfo.bundledID)", "name": "Makera defaults", "kind": "bundled" },
            { "id": "\(ToolSourceInfo.customID)", "name": "My tools", "kind": "custom" }
          ],
          "tools": [
            { "id": "\(bundledToolID)", "name": "Bundled", "shankDiameter": 3.175,
              "toolDiameter": 1.0, "type": "endMill",
              "sourceID": "\(ToolSourceInfo.bundledID)" }
          ] }
        """
        try json.write(to: fileURL, atomically: true, encoding: .utf8)
        return ToolsStore(toolsFileURL: fileURL)
    }

    private func savedLibrary() throws -> ToolLibrary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ToolLibrary.self, from: Data(contentsOf: fileURL))
    }

    private func importedTool(_ name: String, id: UUID = UUID(), presets: [ToolPreset] = []) -> Tool {
        Tool(
            id: id,
            name: name,
            shankDiameter: 6,
            toolDiameter: 3,
            length: 12,
            type: .endMill,
            presets: presets
        )
    }

    // MARK: Loading

    func testLoadsSources() throws {
        let store = try makeStore()
        XCTAssertEqual(store.sources.map(\.id), [ToolSourceInfo.bundledID, ToolSourceInfo.customID])
        XCTAssertEqual(store.source(for: store.tools[0]).kind, .bundled)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    // MARK: Creating tools

    func testAddedToolIsCustom() throws {
        let store = try makeStore()
        let tool = importedTool("Mine")
        try store.add(tool)

        XCTAssertEqual(store.tools.last?.sourceID, ToolSourceInfo.customID)
        XCTAssertEqual(try savedLibrary().tools.last?.sourceID, ToolSourceInfo.customID)
    }

    func testDuplicateOfBundledToolIsCustomAndOriginalIsUntouched() throws {
        let store = try makeStore()
        let copy = try store.duplicate(store.tools[0])

        XCTAssertEqual(copy.sourceID, ToolSourceInfo.customID)
        XCTAssertEqual(copy.name, "Bundled Copy")
        XCTAssertEqual(store.tools.first { $0.id == bundledToolID }?.sourceID, ToolSourceInfo.bundledID)
    }

    // MARK: Import

    func testImportCreatesOneBatchForNewTools() throws {
        let store = try makeStore()
        let counts = try store.importTools(
            [importedTool("A"), importedTool("B")],
            fileName: "shop.tools"
        )

        XCTAssertEqual(counts.added, 2)
        let batch = try XCTUnwrap(counts.batch)
        XCTAssertEqual(batch.name, "shop.tools")
        XCTAssertEqual(batch.kind, .imported)
        XCTAssertEqual(batch.fileName, "shop.tools")
        XCTAssertNotNil(batch.date)

        XCTAssertEqual(store.sources.count, 3)
        XCTAssertEqual(store.sources.last, batch)
        XCTAssertEqual(store.tools.filter { $0.sourceID == batch.id }.map(\.name), ["A", "B"])

        let onDisk = try savedLibrary()
        XCTAssertEqual(onDisk.sources.last?.id, batch.id)
        XCTAssertEqual(onDisk.tools.filter { $0.sourceID == batch.id }.count, 2)
    }

    func testReimportingTheSameToolsCreatesNoBatch() throws {
        let store = try makeStore()
        let tools = [importedTool("A"), importedTool("B")]
        try store.importTools(tools, fileName: "shop.tools")

        let again = try store.importTools(tools, fileName: "shop.tools")

        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.skipped, 2)
        XCTAssertNil(again.batch)
        XCTAssertEqual(store.sources.count, 3)
    }

    func testImportedPresetsMergeIntoAnExistingToolWithoutChangingItsSource() throws {
        let store = try makeStore()
        let preset = ToolPreset(name: "Aluminum", spindleRPM: 12000, feedRate: 500)
        let counts = try store.importTools(
            [importedTool("Bundled again", id: bundledToolID, presets: [preset])],
            fileName: "shop.tools"
        )

        XCTAssertEqual(counts.added, 0)
        XCTAssertEqual(counts.updated, 1)
        XCTAssertNil(counts.batch)
        XCTAssertEqual(store.sources.count, 2)
        XCTAssertEqual(store.tools[0].sourceID, ToolSourceInfo.bundledID)
        XCTAssertEqual(store.tools[0].name, "Bundled")
        XCTAssertEqual(store.tools[0].presets.map(\.name), ["Aluminum"])
    }

    func testMixedImportStampsOnlyTheNewTools() throws {
        let store = try makeStore()
        let counts = try store.importTools(
            [importedTool("Existing", id: bundledToolID), importedTool("Fresh")],
            fileName: "mix.tools"
        )

        let batch = try XCTUnwrap(counts.batch)
        XCTAssertEqual(counts.added, 1)
        XCTAssertEqual(counts.skipped, 1)
        XCTAssertEqual(store.tools.first { $0.id == bundledToolID }?.sourceID, ToolSourceInfo.bundledID)
        XCTAssertEqual(store.tools.first { $0.name == "Fresh" }?.sourceID, batch.id)
    }

    func testSourceSurvivesReload() throws {
        let store = try makeStore()
        let batch = try XCTUnwrap(try store.importTools([importedTool("A")], fileName: "shop.tools").batch)

        let reloaded = ToolsStore(toolsFileURL: fileURL)
        XCTAssertEqual(reloaded.sources.last?.id, batch.id)
        XCTAssertNotNil(reloaded.sources.last?.date)
        XCTAssertEqual(reloaded.source(for: reloaded.tools.last!).name, "shop.tools")
    }
}