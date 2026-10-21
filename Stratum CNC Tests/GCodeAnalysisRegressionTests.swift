import Testing
@testable import Stratum_CNC

struct GCodeAnalysisRegressionTests {
    @Test func tracksModalMovesAndSeparateToolSelection() throws {
        let source = ["T2", "M6", "G1", "X1", "Y2", "X3"]
        let paths = GCodeToolpathAnalyzer.analyze(source.enumerated().map { ($0.offset + 1, $0.element) })
        let path = try #require(paths.first)
        #expect(paths.count == 1)
        #expect(path.toolNumber == 2)
        #expect(path.startLine == 4)
        #expect(path.endLine == 6)
        #expect(path.motionCount == 3)
    }

    @Test func cancelledDrillingDoesNotConsumeFurtherCoordinates() throws {
        let source = ["G81 X1 Y1 Z-2", "X2", "G80", "X3", "G1 X4"]
        let paths = GCodeToolpathAnalyzer.analyze(source.enumerated().map { ($0.offset + 1, $0.element) })
        #expect(paths.count == 2)
        let drill = try #require(paths.first)
        #expect(drill.endLine == 2)
        #expect(drill.motionCount == 2)
        #expect(paths.last?.startLine == 5)
    }
}
