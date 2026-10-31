//
//  ToolSourceTests.swift
//  Stratum CNC
//
//  The source fields must round-trip through JSON. Adjust the @testable import
//  if the module name differs.
//

import XCTest
@testable import Stratum_CNC

final class ToolSourceTests: XCTestCase {

    // The same strategies the store uses: readable dates in the file.
    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testToolDefaultsToTheCustomSource() {
        let tool = Tool(name: "Mine", shankDiameter: 6, toolDiameter: 6, length: 20, type: .endMill)
        XCTAssertEqual(tool.sourceID, ToolSourceInfo.customID)
    }

    func testToolSourceRoundTrips() throws {
        let batch = UUID()
        let tool = Tool(
            name: "Imported",
            shankDiameter: 6,
            toolDiameter: 6,
            length: 20,
            type: .endMill,
            sourceID: batch
        )
        let copy = try decoder.decode(Tool.self, from: try encoder.encode(tool))
        XCTAssertEqual(copy, tool)
        XCTAssertEqual(copy.sourceID, batch)
    }

    func testToolWithoutSourceFailsToDecode() {
        let json = """
        { "id": "91D8C0D2-27C2-47FD-9CB9-3F49431FAA59", "name": "A", "shankDiameter": 3.175,
          "toolDiameter": 1.0, "type": "endMill" }
        """
        XCTAssertThrowsError(try decoder.decode(Tool.self, from: Data(json.utf8)))
    }

    func testImportBatchRoundTrips() throws {
        let batch = ToolSourceInfo(
            name: "shop.tools",
            kind: .imported,
            date: Date(timeIntervalSince1970: 1_790_000_000),
            fileName: "shop.tools"
        )
        let copy = try decoder.decode(ToolSourceInfo.self, from: try encoder.encode(batch))
        XCTAssertEqual(copy, batch)
    }

    func testBundledAndCustomIDsAreFixedAndDistinct() {
        XCTAssertEqual(ToolSourceInfo.bundledID.uuidString, "00000000-0000-0000-0000-00000000B001")
        XCTAssertEqual(ToolSourceInfo.customID.uuidString, "00000000-0000-0000-0000-00000000C001")
        XCTAssertNotEqual(ToolSourceInfo.bundledID, ToolSourceInfo.customID)
        XCTAssertEqual(ToolSourceInfo.bundled.kind, .bundled)
        XCTAssertEqual(ToolSourceInfo.custom.kind, .custom)
    }
}
