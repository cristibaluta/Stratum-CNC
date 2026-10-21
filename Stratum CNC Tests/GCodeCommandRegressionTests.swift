import Testing
@testable import Stratum_CNC

struct GCodeCommandRegressionTests {
    @Test func fractionalCommandsDoNotChangeDistanceMode() {
        let parsed = GCodeParser().parse("G90 G0 X10\nG91.1\nG1 X20")
        #expect(parsed.toolpathSegments.last?.end.x == 20)
    }

    @Test func oversizedUnknownCommandsDoNotTrap() {
        let parsed = GCodeParser().parse("G9999999999999999999999999 M9999999999999999999999999\nG1 X2")
        #expect(parsed.toolpathSegments.last?.end.x == 2)
    }
}
