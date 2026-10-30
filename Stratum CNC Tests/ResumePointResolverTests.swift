import Foundation
import Testing
@testable import Stratum_CNC

struct ResumePointResolverTests {

    private func resolver(_ lines: [String]) -> ResumePointResolver {
        let toolpaths = GCodeToolpathAnalyzer.analyze(lines.enumerated().map { (id: $0.offset + 1, text: $0.element) })
        return ResumePointResolver(lines: lines, toolpaths: toolpaths)
    }

    /// Two passes, each: rapid over the work, plunge, cut, retract.
    private let twoPasses = [
        "G21",              // 1
        "G90",              // 2
        "G0 Z5",            // 3
        "G0 X10 Y10",       // 4
        "G1 Z-1 F100",      // 5
        "G1 X20",           // 6
        "G1 X30",           // 7
        "G0 Z5",            // 8
        "G0 X50 Y50",       // 9
        "G1 Z-1",           // 10
        "G1 X60"            // 11
    ]

    @Test func travelHeightIsTheRapidZOverTheWork() {
        #expect(resolver(twoPasses).retractZ == 5)
    }

    @Test func aLineInTheMiddleOfACutMovesToThePlunge() {
        let point = resolver(twoPasses).resolve(requestedLine: 7)
        #expect(point.line == 5)
        #expect(point.requestedLine == 7)
        #expect(point.isSnapped)
        #expect(point.reason == .toolpathStart)
    }

    @Test func eachPassResumesFromItsOwnStart() {
        let resolver = resolver(twoPasses)
        #expect(resolver.resolve(requestedLine: 6).line == 5)
        #expect(resolver.resolve(requestedLine: 11).line == 10)
        #expect(resolver.resolve(requestedLine: 10).line == 10)
    }

    @Test func aCleanLineIsKept() {
        let point = resolver(twoPasses).resolve(requestedLine: 9)
        #expect(point.line == 9)
        #expect(!point.isSnapped)
        #expect(point.reason == .exact)
    }

    @Test func retractDuringAFeedMovePassStartsAfterTheRetract() {
        // Retract with G1 keeps everything in one cutting toolpath (3...8),
        // so the toolpath start alone would go back to the first pass.
        let lines = [
            "G90",              // 1
            "G0 Z5",            // 2
            "G1 Z-1 F100",      // 3
            "G1 X10",           // 4
            "G1 Z5",            // 5
            "G1 X0 Y5",         // 6
            "G1 Z-1",           // 7
            "G1 X10"            // 8
        ]
        let resolver = resolver(lines)
        let point = resolver.resolve(requestedLine: 8)
        #expect(point.line == 7)
        #expect(point.reason == .retractedBeforePass)
        #expect(resolver.resolve(requestedLine: 4).line == 3)
    }

    @Test func rapidIntoTheMaterialDoesNotLowerTheBar() {
        let lines = [
            "G90",              // 1
            "G0 Z5",            // 2
            "G0 X0 Y0",         // 3
            "G0 Z-2",           // 4  rapid into a hole
            "G1 X5 F100",       // 5
            "G0 Z5"             // 6
        ]
        let resolver = resolver(lines)
        #expect(resolver.retractZ == 5)
        // The cut starts at line 5 with the tool in the hole; the preamble
        // travels over at Z5 and plunges slowly, so that is a fine start.
        #expect(resolver.resolve(requestedLine: 5).line == 5)
    }

    @Test func machineCoordinateRapidsAreNotWorkHeights() {
        let lines = [
            "G90",              // 1
            "G0 Z5",            // 2
            "G1 Z-1 F100",      // 3
            "G1 X5",            // 4
            "G53 G0 Z-1",       // 5  machine coordinates
            "G1 X9"             // 6
        ]
        #expect(resolver(lines).retractZ == 5)
    }

    @Test func noRetractInformationUsesTheLineAsGiven() {
        // No rapid Z moves and no recognised toolpaths.
        let point = ResumePointResolver(lines: ["G1 X1 F100", "G1 X2", "G1 X3"], toolpaths: [])
            .resolve(requestedLine: 3)
        #expect(point.line == 3)
        #expect(point.reason == .none)
        #expect(!point.isSnapped)
    }

    @Test func withoutRetractInformationItFallsBackToTheToolpathStart() {
        let point = resolver(["G1 X1 F100", "G1 X2", "G1 X3"]).resolve(requestedLine: 3)
        #expect(point.line == 1)
        #expect(point.reason == .toolpathStart)
    }

    @Test func linesAreClamped() {
        let resolver = resolver(twoPasses)
        #expect(resolver.resolve(requestedLine: 999).line == 10)
        #expect(resolver.resolve(requestedLine: 0).requestedLine == 1)
    }

    @Test func emptyProgram() {
        let point = ResumePointResolver(lines: [], toolpaths: []).resolve(requestedLine: 4)
        #expect(point.line == 4)
        #expect(point.reason == .none)
    }

    @Test func explainsWhatHappened() {
        let resolver = resolver(twoPasses)
        #expect(resolver.resolve(requestedLine: 7).explanation.contains("line 5"))
        #expect(resolver.resolve(requestedLine: 9).explanation.contains("clean"))
    }
}
