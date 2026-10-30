import Foundation
import Testing
@testable import Stratum_CNC

struct ResumePreambleTests {

    private let program = [
        "G21",              // 1
        "G90",              // 2
        "G54",              // 3
        "M6 T2",            // 4
        "S12000 M3",        // 5
        "G0 Z5",            // 6
        "G0 X10 Y10",       // 7
        "G1 Z-1 F300",      // 8
        "G1 X20",           // 9
        "G1 X30",           // 10
        "G0 Z8",            // 11
        "M5"                // 12
    ]

    // MARK: Modal state

    @Test func replaysTheStateBeforeALine() {
        let (state, maxZ) = GCodeModalState.scan(lines: program, beforeLine: 10)
        #expect(state.units == .millimeters)
        #expect(state.absolute)
        #expect(state.workspace == 54)
        #expect(state.tool == 2)
        #expect(state.spindle == .clockwise)
        #expect(state.spindleSpeed == 12000)
        #expect(state.feed == 300)
        #expect(state.motion == 1)
        #expect(state.x == 20 && state.y == 10 && state.z == -1)
        // The highest Z of the whole program, including lines after the resume line.
        #expect(maxZ == 8)
    }

    @Test func spindleStopIsReplayedToo() {
        let (state, _) = GCodeModalState.scan(lines: program, beforeLine: 13)
        #expect(state.spindle == .off)
        #expect(state.spindleSpeed == 12000)
    }

    @Test func wordsNeedNoSeparator() {
        var scanner = GCodeModalScanner()
        scanner.apply("T1M6")
        scanner.apply("G0X10Y5Z2")
        #expect(scanner.state.tool == 1)
        #expect(scanner.state.x == 10 && scanner.state.y == 5 && scanner.state.z == 2)
    }

    @Test func toolWordMayFollowM6OnTheSameLine() {
        var scanner = GCodeModalScanner()
        scanner.apply("M6 T3")
        #expect(scanner.state.tool == 3)
    }

    @Test func toolWordAloneDoesNotChangeTheTool() {
        var scanner = GCodeModalScanner()
        scanner.apply("M6 T1")
        scanner.apply("T2")
        #expect(scanner.state.tool == 1)
        scanner.apply("M6")
        #expect(scanner.state.tool == 2)
    }

    @Test func commentsAreIgnored() {
        var scanner = GCodeModalScanner()
        scanner.apply("(M3 S9000) G0 X1 ; M5 Y9")
        #expect(scanner.state.spindle == .off)
        #expect(scanner.state.x == 1)
        #expect(scanner.state.y == nil)
    }

    @Test func relativeMovesAddToAKnownPosition() {
        var scanner = GCodeModalScanner()
        scanner.apply("G90 G0 X10 Y10 Z0")
        scanner.apply("G91")
        scanner.apply("G1 X5 Z-1")
        #expect(scanner.state.x == 15 && scanner.state.y == 10 && scanner.state.z == -1)
        #expect(!scanner.state.absolute)
    }

    @Test func relativeMovesFromAnUnknownPositionStayUnknown() {
        var scanner = GCodeModalScanner()
        scanner.apply("G91")
        scanner.apply("G1 X5")
        #expect(scanner.state.x == nil)
    }

    @Test func inchesAreKeptInMillimeters() {
        var scanner = GCodeModalScanner()
        scanner.apply("G20 G90")
        scanner.apply("G1 X1 Y2 Z-0.5")
        #expect(scanner.state.units == .inches)
        #expect(abs((scanner.state.x ?? 0) - 25.4) < 1e-9)
        #expect(abs((scanner.state.z ?? 0) + 12.7) < 1e-9)
    }

    @Test func machineCoordinateMovesDoNotChangeWorkPosition() {
        var scanner = GCodeModalScanner()
        scanner.apply("G90 G0 X5 Y5 Z2")
        scanner.apply("G53 G0 Z0")
        #expect(scanner.state.z == 2)
    }

    @Test func clearancePositionLosesThePosition() {
        var scanner = GCodeModalScanner()
        scanner.apply("G90 G0 X5 Y5 Z2")
        scanner.apply("G28")
        #expect(!scanner.state.hasKnownPosition)
    }

    @Test func cannedCyclesAreFlagged() {
        var scanner = GCodeModalScanner()
        scanner.apply("G81 X1 Y1 Z-3 R2")
        #expect(scanner.state.motion == nil)
        #expect(!scanner.state.warnings.isEmpty)
    }

    // MARK: Preamble

    @Test func buildsThePreamble() {
        let (state, maxZ) = GCodeModalState.scan(lines: program, beforeLine: 10)
        let preamble = ResumePreambleBuilder.build(state: state, maxZ: maxZ, resumeLine: 10)
        #expect(preamble.canResume)
        #expect(preamble.lines == [
            "; --- Resume preamble: continuing from line 10 ---",
            "G21", "G17", "G54", "G90",
            "M6 T2",
            "G0 Z8",
            "M3 S12000",
            "G4 P3",
            "G0 X20 Y10",
            "G1 Z-1 F100",
            "F300",
            "G1",
            "; --- End of resume preamble ---"
        ])
    }

    @Test func toolChangeIsOptional() {
        let (state, maxZ) = GCodeModalState.scan(lines: program, beforeLine: 10)
        var options = ResumeOptions()
        options.includeToolChange = false
        let preamble = ResumePreambleBuilder.build(state: state, maxZ: maxZ, resumeLine: 10, options: options)
        #expect(!preamble.lines.contains("M6 T2"))
    }

    @Test func spindleIsNotStartedWhenTheProgramHadItOff() {
        let (state, maxZ) = GCodeModalState.scan(lines: program, beforeLine: 13)
        let preamble = ResumePreambleBuilder.build(state: state, maxZ: maxZ, resumeLine: 13)
        #expect(!preamble.lines.contains { $0.hasPrefix("M3") || $0.hasPrefix("M4") })
        #expect(!preamble.lines.contains { $0.hasPrefix("G4") })
    }

    @Test func travelsAtTheProgramsClearanceHeight() {
        let lines = ["G90", "G0 X1 Y1 Z4", "G1 Z2", "G1 X5"]
        let (state, maxZ) = GCodeModalState.scan(lines: lines, beforeLine: 3)
        let preamble = ResumePreambleBuilder.build(state: state, maxZ: maxZ, resumeLine: 3)
        #expect(preamble.lines.contains("G0 Z4"))
        // Already at travel height, so no plunge.
        #expect(!preamble.lines.contains { $0.hasPrefix("G1 Z") })
    }

    @Test func relativeModeIsRestoredLast() {
        let lines = ["G90", "G0 X0 Y0 Z5", "G91", "G1 X5", "G1 X5"]
        let (state, maxZ) = GCodeModalState.scan(lines: lines, beforeLine: 5)
        let preamble = ResumePreambleBuilder.build(state: state, maxZ: maxZ, resumeLine: 5)
        #expect(preamble.lines.contains("G0 X5 Y0"))
        #expect(preamble.lines[preamble.lines.count - 2] == "G91")
    }

    @Test func inchPreambleUsesInches() {
        let lines = ["G20", "G90", "G0 Z0.5", "G0 X1 Y2", "G1 Z-0.25 F10", "G1 X2"]
        let (state, maxZ) = GCodeModalState.scan(lines: lines, beforeLine: 6)
        let preamble = ResumePreambleBuilder.build(state: state, maxZ: maxZ, resumeLine: 6)
        #expect(preamble.lines.contains("G20"))
        #expect(preamble.lines.contains("G0 X1 Y2"))
        #expect(preamble.lines.contains("G1 Z-0.25 F3.937"))
    }

    @Test func unknownPositionCannotBeResumed() {
        let lines = ["G91", "G1 X5", "G1 X5"]
        let (state, maxZ) = GCodeModalState.scan(lines: lines, beforeLine: 3)
        let preamble = ResumePreambleBuilder.build(state: state, maxZ: maxZ, resumeLine: 3)
        #expect(!preamble.canResume)
        #expect(!preamble.warnings.isEmpty)
        #expect(!preamble.lines.contains { $0.hasPrefix("G0 X") })
    }

    @Test func formatsNumbersCompactly() {
        #expect(ResumePreambleBuilder.format(5) == "5")
        #expect(ResumePreambleBuilder.format(0.30000000000000004) == "0.3")
        #expect(ResumePreambleBuilder.format(-0.00001) == "0")
        #expect(ResumePreambleBuilder.format(12.34567) == "12.3457")
    }

    // MARK: Resume file

    @Test func resumeFileContinuesFromTheLine() throws {
        let file = try #require(ResumeFileBuilder.build(lines: program, resumeLine: 10))
        let lines = file.contents.components(separatedBy: "\n")
        let preambleCount = file.preamble.lines.count

        #expect(Array(lines[..<preambleCount]) == file.preamble.lines)
        #expect(Array(lines[preambleCount...]) == Array(program[9...]))
    }

    @Test func resumeFileLinesMapBackToTheOriginal() throws {
        let file = try #require(ResumeFileBuilder.build(lines: program, resumeLine: 10))
        let firstProgramLine = file.preamble.lines.count + 1
        #expect(file.originalLine(forResumeFileLine: firstProgramLine) == 10)
        #expect(file.originalLine(forResumeFileLine: firstProgramLine + 2) == 12)
    }

    @Test func resumeLineIsClamped() throws {
        let file = try #require(ResumeFileBuilder.build(lines: program, resumeLine: 999))
        #expect(file.resumeLine == program.count)
        #expect(ResumeFileBuilder.build(lines: [], resumeLine: 1) == nil)
    }
}
