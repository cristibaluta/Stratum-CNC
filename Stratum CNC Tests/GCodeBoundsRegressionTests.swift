import Testing
@testable import Stratum_CNC

struct GCodeBoundsRegressionTests {
    @Test func unitsApplyToCoordinatesBeforeTheUnitWord() throws {
        let prefix = "G0 X0 Y0\n"
        let first = try #require(GCodeBounds.cutting(in: prefix + "G20 G1 X1 Y2"))
        let last = try #require(GCodeBounds.cutting(in: prefix + "G1 X1 Y2 G20"))
        #expect(first == last)
        #expect(last.maxX == 25.4)
        #expect(last.maxY == 50.8)
    }
}
