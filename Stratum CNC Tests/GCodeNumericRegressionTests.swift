import Testing
@testable import Stratum_CNC

struct GCodeNumericRegressionTests {
    @Test func oversizedCoordinatesDoNotPoisonFollowingGeometry() {
        let parsed = GCodeParser().parse("G1 X1\nG1 X1e309\nG2 X2 I1e100\nG1 X3")
        #expect(parsed.lines[1].geometryCount == 0)
        #expect(parsed.lines[2].geometryCount == 0)
        #expect(parsed.toolpathSegments.count == 2)
        #expect(parsed.toolpathSegments.last?.start.x == 1)
        #expect(parsed.toolpathSegments.last?.end.x == 3)
        #expect(parsed.toolpathSegments.allSatisfy { segment in
            [segment.start.x, segment.start.y, segment.start.z,
             segment.end.x, segment.end.y, segment.end.z].allSatisfy(\.isFinite)
        })
    }
}
