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
    // MARK: - Macro preview

    private func seg(_ a: SIMD3<Float>, _ b: SIMD3<Float>, flags: UInt32 = ToolpathFlags.cutting) -> ToolpathSegment {
        ToolpathSegment(start: a, end: b, lineNumber: 1, flags: flags)
    }

    @Test @MainActor func macroPreviewKeepsProgramGeometryAndRestoresIt() {
        let scene = CanvasSceneModel()
        let program = [seg(.init(0, 0, 0), .init(10, 0, 0)),
                       seg(.init(10, 0, 0), .init(10, 10, 0))]
        scene.updateToolpath(program)
        let before = scene.renderObjects.filter { $0.role == .toolpathCutting }
        #expect(before.count == 1)

        scene.showMacroPreview([seg(.init(0, 0, 0), .init(0, 0, -2))])

        // Program is still in the scene, just not drawn.
        let hidden = scene.renderObjects.filter { $0.role == .toolpathCutting }
        #expect(hidden.map(\.id) == before.map(\.id))
        #expect(hidden.first?.visibleVertexCount == 0)
        #expect(scene.renderObjects.contains { $0.role == .macroCutting })
        #expect(scene.isMacroPreviewActive)

        // Scrubbing can't bring the program back over the macro.
        scene.setToolpathVisibleVertexCounts(rapid: 0, cutting: 4)
        #expect(scene.renderObjects.first { $0.role == .toolpathCutting }?.visibleVertexCount == 0)

        scene.hideMacroPreview(restoringProgramVertexCounts: (rapid: 0, cutting: 4))
        let after = scene.renderObjects.filter { $0.role == .toolpathCutting }
        #expect(after.map(\.id) == before.map(\.id))
        #expect(after.first?.visibleVertexCount == 4)
        #expect(!scene.renderObjects.contains { $0.role == .macroCutting || $0.role == .macroRapid })
        #expect(!scene.isMacroPreviewActive)
    }

    @Test @MainActor func macroPreviewIsDrawnAtTheToolPosition() throws {
        let scene = CanvasSceneModel()
        scene.showMacroPreview([seg(.init(0, 0, 0), .init(1, 0, -2))])
        scene.setMacroOrigin(.init(30, 40))

        let macro = try #require(scene.renderObjects.first { $0.role == .macroCutting })
        #expect(macro.points == [.init(30, 40, 0), .init(31, 40, -2)])
    }

    @Test @MainActor func boundingBoxComesBackAfterMacroPreview() {
        let scene = CanvasSceneModel()
        let program = [seg(.init(0, 0, 0), .init(10, 10, -1))]
        scene.updateToolpath(program)
        scene.updateBoundingBox(segments: program, toolRadii: [0, 1])
        #expect(scene.renderObjects.contains { $0.role == .boundingBox })

        scene.showMacroPreview([])
        #expect(!scene.renderObjects.contains { $0.role == .boundingBox })

        scene.hideMacroPreview(restoringProgramVertexCounts: (rapid: 0, cutting: 2))
        #expect(scene.renderObjects.contains { $0.role == .boundingBox })
    }
}
