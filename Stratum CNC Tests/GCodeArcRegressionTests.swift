import Testing
@testable import Stratum_CNC
import StratumLink

struct GCodeArcRegressionTests {
    @Test(arguments: ["G2 I-5", "G3 I-5", "G2 I-5 J0", "G3 I-5 J0"])
    func fullCirclesWithoutEndpoints(arc: String) throws {
        let source = "G0 X10 Y5\n\(arc)"
        let parsed = GCodeParser().parse(source)
        let arcSegments = parsed.toolpathSegments.filter { $0.lineNumber == 2 }
        #expect(arcSegments.count == 72)
        #expect(arcSegments.last?.end == arcSegments.first?.start)
        let bounds = try #require(GCodeBounds.cutting(in: source))
        #expect(abs(bounds.minX) < 0.0001)
        #expect(abs(bounds.maxX - 10) < 0.0001)
        #expect(abs(bounds.minY) < 0.0001)
        #expect(abs(bounds.maxY - 10) < 0.0001)
    }

    @Test func omittedZeroCenterOffsetStillDrawsArc() {
        let parsed = GCodeParser().parse("G0 X10 Y0\nG3 X0 Y10 I-10")
        let arc = parsed.toolpathSegments.filter { $0.lineNumber == 2 }
        #expect(arc.count == 18)
        #expect(arc.contains { $0.end.x > 6 && $0.end.y > 6 })
    }
}
