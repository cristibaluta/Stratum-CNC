import Foundation
import Testing
@testable import Stratum_CNC

struct CanvasSceneTests {
    @Test @MainActor func replacingProgramInvalidatesCarvedHeights() async throws {
        let scene = CanvasSceneModel()
        scene.renderMode = .heightmap
        scene.heightmapCellSize = 1
        let stock = StockMaterial(name: "Test", material: .aluminum,
                                  geometry: .rectangular(width: 5, height: 5, depth: 2))
        let tool = ToolSpec(name: "Test", diameterMM: 1, flutes: 2, kind: .endMill)
        func segments(at x: Float) -> [ToolpathSegment] {
            [ToolpathSegment(start: .init(x, 0.5, 0), end: .init(x, 0.5, -1),
                             lineNumber: 1, flags: ToolpathFlags.cutting)]
        }
        func waitForCarve() async throws {
            let deadline = Date().addingTimeInterval(5)
            while scene.isComputingHeightmap && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(!scene.isComputingHeightmap)
        }
        let first = segments(at: 0.5)
        scene.updateToolpath(first)
        scene.updateHeightmap(stock: stock, segments: first[...], tool: tool)
        try await waitForCarve()
        let second = segments(at: 3.5)
        scene.updateToolpath(second)
        scene.updateHeightmap(stock: stock, segments: second[...], tool: tool)
        try await waitForCarve()
        let mesh = try #require(scene.heightmapMesh)
        #expect(mesh.vertices.contains { $0.normal.z == 1 && $0.position.x == 3 && $0.position.z == -1 })
        #expect(!mesh.vertices.contains { $0.normal.z == 1 && $0.position.x == 0 && $0.position.z == -1 })
    }
}
