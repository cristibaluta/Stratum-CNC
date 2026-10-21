import Testing
@testable import Stratum_CNC

struct GerberImportTests {
    @Test func interpolationCommandsKeepCoordinatesOnTheSameBlock() throws {
        let result = GerberParser.parseFile("""
            %FSLAX24Y24*%
            %MOMM*%
            X0Y0D02*
            G01X10000Y20000D01*
            """, name: "outline.gm1")
        #expect(result.entities.count == 1)
        guard case let .line(a, b, _, _) = try #require(result.entities.first) else {
            Issue.record("Expected an outline segment")
            return
        }
        #expect(a.x == 0 && a.y == 0)
        #expect(b.x == 1 && b.y == 2)
    }

    @Test func drillFilesProduceHoleGeometry() throws {
        let result = GerberParser.parseFile("""
            M48
            METRIC,LZ,000.000
            T01C0.8
            %
            T01
            X10000Y20000
            M30
            """, name: "holes.DRL")
        #expect(result.entities.count == 1)
        guard case let .circle(center, radius, layer, _) = try #require(result.entities.first) else {
            Issue.record("Expected a drill hole circle")
            return
        }
        #expect(center.x == 10)
        #expect(center.y == 20)
        #expect(radius == 0.4)
        #expect(layer == "holes.DRL")
    }
}
