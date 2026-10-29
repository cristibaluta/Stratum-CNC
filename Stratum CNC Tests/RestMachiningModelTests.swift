//
//  RestMachiningModelTests.swift
//  Stratum CNC Tests
//

import Foundation
import Testing
@testable import Stratum_CNC

struct RestMachiningModelTests {

    private func rest(sourceID: UUID?) -> ToolpathData {
        var toolpath = ToolpathData(id: UUID(),
                                    name: "Rest 1",
                                    tool: Tool(id: UUID(),
                                               name: "2mm",
                                               shankDiameter: 3,
                                               toolDiameter: 2,
                                               length: 12,
                                               type: .endMill,
                                               group: nil,
                                               tipAngle: nil,
                                               presets: []),
                                    startZ: 0,
                                    endZ: -1,
                                    contour: .onContour,
                                    ramping: RampingSettings(enabled: false, type: .none, angle: 2, length: 10),
                                    feedRate: 800,
                                    plungeRate: 400,
                                    spindleRPM: 12000,
                                    stepDown: 0.5,
                                    stepOverPercent: 40,
                                    safeZ: 3)
        toolpath.operation.kind = .restMachining
        toolpath.operation.restSourceID = sourceID
        return toolpath
    }

    @Test func restToolpathSurvivesEncodeAndDecode() throws {
        let sourceID = UUID()
        let original = rest(sourceID: sourceID)
        let decoded = try JSONDecoder().decode(ToolpathData.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.operation.kind == .restMachining)
        #expect(decoded.operation.restSourceID == sourceID)
    }

    @Test func oldProjectsWithoutASourceStillDecode() throws {
        var legacy = rest(sourceID: nil)
        legacy.operation.kind = .pocket
        let decoded = try JSONDecoder().decode(ToolpathData.self, from: JSONEncoder().encode(legacy))
        #expect(decoded.operation.restSourceID == nil)
    }

    @Test func geometryIsTheLinkedSource() {
        #expect(rest(sourceID: UUID()).hasGeometry)
        #expect(!rest(sourceID: nil).hasGeometry)
    }
}
