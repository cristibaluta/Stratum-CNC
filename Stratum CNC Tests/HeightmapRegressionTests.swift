import Testing
@testable import Stratum_CNC

struct HeightmapRegressionTests {
    @Test(arguments: [false, true])
    func verticalFeedCutsToDeepestEndpoint(retracting: Bool) {
        var grid = HeightmapGrid(originX: 0, originY: 0, width: 3, height: 3,
                                 cellSize: 1, topZ: 0)
        let tool = ToolSpec(name: "Test", diameterMM: 1, flutes: 2, kind: .endMill)
        let segment = ToolpathSegment(start: .init(1.5, 1.5, retracting ? -2 : 1),
                                      end: .init(1.5, 1.5, retracting ? 1 : -2),
                                      lineNumber: 1, flags: ToolpathFlags.cutting)
        grid.carve(segment: segment, tool: tool)
        #expect(grid[1, 1] == -2)
        #expect(grid[0, 0] == 0)
    }
}
