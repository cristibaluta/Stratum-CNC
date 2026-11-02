import Foundation
import Testing
import simd
@testable import Stratum_CNC

private enum STEPViewerFixture {
    static func content(id: UUID = UUID()) throws -> STEPViewerContent {
        let body = STEPBodyID(representationID: 10, entityID: 20)
        let edges = [-0.25, 0.25].enumerated().map { index, z in
            STEPEdge(id: STEPEdgeID(importID: id, bodyID: body, entityID: index + 1), kind: .line,
                     points: [SIMD3<Double>(-0.8, 0, z), SIMD3<Double>(0.8, 0, z)],
                     startVertexID: index * 2, endVertexID: index * 2 + 1, adjacentFaceIDs: [])
        }
        var model = STEPEdgeModel(importID: id)
        model.edges = edges
        model.bodies = [STEPBodyInfo(id: body, contextID: 30, unitScaleToMM: 1, unitsAssumed: false)]
        model.bounds = STEPBounds(min: SIMD3<Double>(-0.8, 0, -0.25), max: SIMD3<Double>(0.8, 0, 0.25))
        model.reachableEdgeCount = 2
        return try STEPViewerContent(model: model, geometry: STEPDisplayGeometry(model: model))
    }

    static var matrix: simd_float4x4 {
        var result = matrix_identity_float4x4
        result.columns.3.z = 0.5
        return result
    }

    // Minimal scoped edge topology, deliberately not a CAD solid validation fixture.
    static let source = """
        ISO-10303-21; HEADER; ENDSEC; DATA;
        #1=CARTESIAN_POINT('',(0.,0.,0.));
        #2=CARTESIAN_POINT('',(10.,0.,0.));
        #3=VERTEX_POINT('',#1); #4=VERTEX_POINT('',#2);
        #5=LINE('',#1,#16); #6=EDGE_CURVE('',#3,#4,#5,.T.);
        #7=ORIENTED_EDGE('',*,*,#6,.T.); #8=EDGE_LOOP('',(#7));
        #9=FACE_OUTER_BOUND('',#8,.T.); #10=ADVANCED_FACE('',(#9),#18,.T.);
        #11=CLOSED_SHELL('',(#10)); #12=MANIFOLD_SOLID_BREP('',#11);
        #13=ADVANCED_BREP_SHAPE_REPRESENTATION('',(#12),#14);
        #14=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#15)) REPRESENTATION_CONTEXT('',''));
        #15=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));
        #16=VECTOR('',#17,1.); #17=DIRECTION('',(1.,0.,0.));
        #18=PLANE('',#19); #19=AXIS2_PLACEMENT_3D('',#1,$,$);
        ENDSEC; END-ISO-10303-21;
        """
}

struct STEPViewerRegressionTests {
    @Test func batchingPreservesEdgeRangesAndCentersLargeCoordinates() throws {
        let content = try STEPViewerFixture.content()
        #expect(content.geometry.bodies.count == 1)
        #expect(content.geometry.bodies[0].points.count == 4)
        #expect(content.geometry.bodies[0].edges.map(\.vertices) == [0..<2, 2..<4])
        var model = content.model
        let offset = SIMD3<Double>(1e12, -1e12, 1e12)
        model.edges = model.edges.map { edge in
            STEPEdge(id: edge.id, kind: edge.kind, points: edge.points.map { $0 + offset },
                     startVertexID: edge.startVertexID, endVertexID: edge.endVertexID, adjacentFaceIDs: [])
        }
        model.bounds = STEPBounds(min: model.bounds!.min + offset, max: model.bounds!.max + offset)
        let centered = try STEPDisplayGeometry(model: model)
        #expect(centered.origin == offset)
        #expect(abs(centered.bodies[0].points[0].x + 0.8) < 0.001)
    }

    @Test func pickingUsesViewPointsAndDepthForOverlaps() throws {
        let content = try STEPViewerFixture.content()
        let geometry = content.geometry
        let size = CGSize(width: 200, height: 100)
        #expect(geometry.hitTest(at: CGPoint(x: 100, y: 55), viewport: size, matrix: STEPViewerFixture.matrix) == content.model.edges[0].id)
        #expect(geometry.hitTest(at: CGPoint(x: 100, y: 57), viewport: size, matrix: STEPViewerFixture.matrix) == nil)
        // Backing pixels never enter the calculation. Resizing still uses a six-point tolerance.
        #expect(geometry.hitTest(at: CGPoint(x: 200, y: 105), viewport: CGSize(width: 400, height: 200), matrix: STEPViewerFixture.matrix) != nil)
        #expect(geometry.hitTest(at: CGPoint(x: 100, y: 50), viewport: size, matrix: STEPViewerFixture.matrix,
                                 hiddenBodies: [content.model.bodies[0].id]) == nil)
        #expect(geometry.hitTest(at: .zero, viewport: .zero, matrix: STEPViewerFixture.matrix) == nil)
    }

    @Test func projectionClipsNearFarAndOffscreenSegments() throws {
        let viewport = CGSize(width: 200, height: 100)
        let matrix = matrix_identity_float4x4
        #expect(STEPDisplayGeometry.projectSegment(SIMD3<Float>(-1,0,-2), SIMD3<Float>(1,0,-1), matrix: matrix, viewport: viewport) == nil)
        #expect(STEPDisplayGeometry.projectSegment(SIMD3<Float>(-1,0,2), SIMD3<Float>(1,0,3), matrix: matrix, viewport: viewport) == nil)
        #expect(STEPDisplayGeometry.projectSegment(SIMD3<Float>(2,0,0.5), SIMD3<Float>(3,0,0.5), matrix: matrix, viewport: viewport) == nil)
        let clipped = try #require(STEPDisplayGeometry.projectSegment(SIMD3<Float>(-1,0,-1), SIMD3<Float>(1,0,1), matrix: matrix, viewport: viewport))
        #expect(abs(clipped.0.x - 100) < 0.001)
        #expect(abs(clipped.0.z) < 0.001)
        #expect(abs(clipped.1.z - 1) < 0.001)
    }

    @Test func cameraOrbitZoomAndLargeModelFitRemainPickable() throws {
        let content = try STEPViewerFixture.content()
        let camera = Camera()
        camera.fit(center: .zero, radius: 1, aspect: 2, adaptive: true)
        camera.aspectRatio = 2
        let size = CGSize(width: 800, height: 400)
        for zoom: Float in [0.5, 1, 3] {
            camera.distance = zoom
            camera.orbit(yaw: 0.3, pitch: 0.2)
            let points = content.geometry.bodies[0].points
            let segment = try #require(STEPDisplayGeometry.projectSegment(points[0], points[1], matrix: camera.updateMatrix(), viewport: size))
            let middle = (segment.0 + segment.1) / 2
            #expect(content.geometry.hitTest(at: CGPoint(x: CGFloat(middle.x), y: CGFloat(middle.y)), viewport: size, matrix: camera.updateMatrix()) != nil)
        }
        camera.fit(center: .zero, radius: 50_000, aspect: 2, adaptive: true)
        #expect(camera.distance > 2000)
        #expect(camera.zoomLimits.upperBound > camera.distance)
        #expect(STEPDisplayGeometry.projectSegment(SIMD3<Float>(0,0,-40_000), SIMD3<Float>(0,0,40_000), matrix: camera.updateMatrix(), viewport: size) != nil)
        let legacy = Camera()
        legacy.fit(center: .zero, radius: 50_000, aspect: 2)
        #expect(legacy.distance == 2000)
        #expect(legacy.zoomLimits == 2...2000)
    }

    @Test func draggingBackToStartIsNotAClick() {
        var tracker = CanvasClickTracker()
        tracker.begin(at: .zero)
        let clicked = tracker.end(at: CGPoint(x: 1, y: 1))
        #expect(clicked)
        tracker.begin(at: .zero)
        tracker.move(to: CGPoint(x: 10, y: 0))
        #expect(tracker.isDragging)
        let dragged = tracker.end(at: .zero)
        let duplicateRelease = tracker.end(at: .zero)
        #expect(!dragged)
        #expect(!duplicateRelease)
    }

    @Test @MainActor func selectionOnlyRebuildsHighlightAndHonorsVisibility() throws {
        let scene = STEPDocumentScene(content: try STEPViewerFixture.content())
        let baseIDs = scene.baseObjects.map(\.id)
        let edges = scene.content.model.edges.map(\.id)
        scene.select(edges[0], extend: false)
        #expect(scene.selectedEdges == [edges[0]])
        #expect(scene.selectionObjects.first?.role == .modelSelection)
        scene.select(edges[1], extend: true)
        #expect(scene.selectedEdges.count == 2)
        #expect(scene.selectionObjects.first?.points.count == 4)
        scene.select(edges[0], extend: true)
        #expect(scene.selectedEdges == [edges[1]])
        #expect(scene.baseObjects.map(\.id) == baseIDs)
        scene.setBodyVisible(edges[1].bodyID, false)
        #expect(scene.selectedEdges.isEmpty)
        #expect(scene.visibleObjects.isEmpty)
        scene.select(edges[1], extend: false)
        #expect(scene.selectedEdges.isEmpty)
        scene.setBodyVisible(edges[1].bodyID, true)
        scene.select(edges[0], extend: false)
        scene.isModelVisible = false
        #expect(scene.selectionObjects.isEmpty)
        scene.isModelVisible = true
        scene.select(edges[0], extend: false)
        scene.select(nil, extend: true)
        #expect(scene.selectedEdges.isEmpty)
    }

    @Test @MainActor func supersededImportsCannotReplaceLatestScene() async throws {
        let gate = STEPTestLoader()
        let workspace = STEPWorkspace(loader: { _, _ in try await gate.load() })
        let id = UUID()
        let source = STEPSourceReference(id: id, name: "test.step", url: URL(fileURLWithPath: "/test.step"))
        let content = try STEPViewerFixture.content(id: id)
        var finishes = 0
        workspace.load(source) { finishes += 1 }
        try await waitForRequests(gate, count: 1)
        workspace.load(source) { finishes += 1 }
        try await waitForRequests(gate, count: 2)
        await gate.complete(1, content: content)
        try await waitUntil { workspace.documents[id] != nil }
        let latest = try #require(workspace.documents[id])
        latest.select(content.model.edges[0].id, extend: false)
        await gate.complete(0, content: content) // loader deliberately ignores cancellation
        try await waitUntil { finishes == 2 }
        #expect(workspace.documents[id] === latest)
        #expect(latest.selectedEdges.count == 1)
        #expect(workspace.loadingIDs.isEmpty)
    }

    @Test @MainActor func cancellationRemovalAndClearDiscardLateResults() async throws {
        for action in 0..<3 {
            let gate = STEPTestLoader()
            let workspace = STEPWorkspace(loader: { _, _ in try await gate.load() })
            let id = UUID()
            let source = STEPSourceReference(id: id, name: "test.step", url: URL(fileURLWithPath: "/test.step"))
            var finished = false
            workspace.load(source) { finished = true }
            try await waitForRequests(gate, count: 1)
            switch action {
                case 0: workspace.cancel(id)
                case 1: workspace.remove(id)
                default: workspace.clear()
            }
            await gate.complete(0, content: try STEPViewerFixture.content(id: id))
            try await waitUntil { finished }
            #expect(workspace.documents.isEmpty)
            #expect(workspace.loadingIDs.isEmpty)
            if action == 0 { #expect(workspace.errors[id] != nil) }
            else { #expect(workspace.sources.isEmpty) }
        }
    }

    @Test @MainActor func projectReopenRestoresSourceIdentityButNotSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = Project(id: UUID(), name: "STEP reopen", createdAt: Date(), modifiedAt: Date(), bookmark: nil, path: nil)
        let paths = try ProjectPaths(project: project, documentsDirectory: root)
        try FileManager.default.createDirectory(at: paths.assetsDirectory, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("part.STP")
        try STEPViewerFixture.source.write(to: original, atomically: true, encoding: .utf8)
        var activeAccesses = 0
        let model = ProjectModel(project: project, paths: paths,
                                 beginFolderAccess: { activeAccesses += 1; return true },
                                 endFolderAccess: { activeAccesses -= 1 })
        let asset = try model.importAsset(from: original)
        let id = try #require(asset.stepImportID)
        try model.loadSTEPAsset(asset)
        #expect(activeAccesses == 1)
        try await waitUntil { model.camModel.stepWorkspace.loadingIDs.isEmpty }
        #expect(activeAccesses == 0)
        let scene = try #require(model.camModel.stepWorkspace.documents[id])
        let edgeID = try #require(scene.content.model.edges.first).id
        scene.select(edgeID, extend: false)
        #expect(model.camModel.canvasState.objects.isEmpty)
        try model.save()
        try FileManager.default.removeItem(at: original) // source copy must be independent
        let reopened = ProjectModel(project: project, paths: paths)
        try await waitUntil { reopened.camModel.stepWorkspace.loadingIDs.isEmpty }
        let restored = try #require(reopened.camModel.stepWorkspace.documents[id])
        #expect(restored.content.model.edges.first?.id == edgeID)
        #expect(restored.selectedEdges.isEmpty)
        #expect(reopened.projectData.assets?.first?.objects == nil)
        try reopened.removeSTEPSource(id)
        let afterRemoval = ProjectModel(project: project, paths: paths)
        #expect(afterRemoval.camModel.stepWorkspace.sources.isEmpty)
    }

    @Test func legacyAssetMetadataDecodesWithoutSTEPFields() throws {
        let asset = try JSONDecoder().decode(AssetData.self, from: Data("{\"name\":\"part.svg\"}".utf8))
        #expect(asset.stepImportID == nil)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for STEP load")
        throw STEPParseError("STEP test timed out")
    }

    private func waitForRequests(_ loader: STEPTestLoader, count: Int) async throws {
        for _ in 0..<1000 {
            if await loader.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw STEPParseError("Loader did not start")
    }
}

private actor STEPTestLoader {
    private var pending: [CheckedContinuation<STEPViewerContent, any Error>?] = []
    var count: Int { pending.count }
    func load() async throws -> STEPViewerContent {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func complete(_ index: Int, content: STEPViewerContent) {
        pending[index]?.resume(returning: content)
        pending[index] = nil
    }
}
