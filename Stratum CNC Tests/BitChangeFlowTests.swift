import Foundation
import Testing
@testable import Stratum_CNC

struct BitChangeFlowTests {

    private let program = [
        "G90",              // 1
        "G0 Z5",            // 2
        "G0 X0 Y0",         // 3
        "G1 Z-1 F100",      // 4
        "G1 X10",           // 5
        "G1 X20",           // 6
        "G1 X30",           // 7
        "G1 X40",           // 8
        "G0 Z5"             // 9
    ]

    private func resolver() -> ResumePointResolver {
        let toolpaths = GCodeToolpathAnalyzer.analyze(program.enumerated().map { (id: $0.offset + 1, text: $0.element) })
        return ResumePointResolver(lines: program, toolpaths: toolpaths)
    }

    // MARK: Backing up

    @Test func backsUpAlongTheCut() {
        // Cutting from line 4 (the plunge, 6 mm) then 10 mm per line.
        let point = resolver().backedUp(from: 8, millimeters: 15)
        #expect(point.line == 6)
        #expect(point.requestedLine == 8)
        #expect(point.reason == .backedUp(millimeters: 15))
        #expect(point.explanation.contains("15 mm"))
    }

    @Test func neverBacksUpPastTheStartOfThePass() {
        #expect(resolver().backedUp(from: 8, millimeters: 1000).line == 4)
    }

    @Test func backingUpZeroStaysPut() {
        let point = resolver().backedUp(from: 8, millimeters: 0)
        #expect(point.line == 8)
        #expect(point.explanation.contains("nothing to back up"))
    }

    // MARK: Machine condition

    @Test func readsTheMachineState() {
        #expect(BitChangeFlow.MachineCondition(machineState: "Run") == .moving)
        #expect(BitChangeFlow.MachineCondition(machineState: "Hold:0") == .moving)
        #expect(BitChangeFlow.MachineCondition(machineState: "Pause") == .suspended)
        #expect(BitChangeFlow.MachineCondition(machineState: "Alarm") == .alarm)
        #expect(BitChangeFlow.MachineCondition(machineState: "Idle") == .ready)
        #expect(BitChangeFlow.MachineCondition(machineState: nil) == .unknown)
    }

    // MARK: Steps

    @Test func theMachineMustBeIdleBeforeReplacingTheBit() {
        var flow = BitChangeFlow(sourceLine: 8)
        for condition in [BitChangeFlow.MachineCondition.moving, .suspended, .alarm, .unknown] {
            #expect(!flow.canAdvance(machine: condition))
            #expect(flow.blocker(machine: condition) != nil)
        }
        #expect(flow.canAdvance(machine: .ready))
        #expect(flow.blocker(machine: .ready) == nil)
        let advanced = flow.advance(machine: .ready)
        #expect(advanced)
        #expect(flow.step == .replace)
    }

    @Test func aBitReplacedByHandMustBeMeasured() {
        var flow = BitChangeFlow(sourceLine: 8)
        flow.advance(machine: .ready)

        #expect(flow.installation == .byHand)
        #expect(!flow.canAdvance(machine: .ready))
        #expect(flow.blocker(machine: .ready)?.contains("Measure") == true)

        flow.calibrationSent = true
        #expect(flow.canAdvance(machine: .ready))
        // Not while the machine is still measuring.
        #expect(!flow.canAdvance(machine: .moving))
        let advanced = flow.advance(machine: .ready)
        #expect(advanced)
        #expect(flow.step == .restart)
    }

    @Test func anAutomaticChangeNeedsAToolNumber() {
        var flow = BitChangeFlow(sourceLine: 8)
        flow.advance(machine: .ready)
        flow.setInstallation(.automatic(tool: 0))
        #expect(!flow.canAdvance(machine: .ready))
        flow.setInstallation(.automatic(tool: 3))
        #expect(flow.canAdvance(machine: .ready))
    }

    @Test func changingTheInstallationForgetsTheMeasurement() {
        var flow = BitChangeFlow(sourceLine: 8)
        flow.calibrationSent = true
        flow.setInstallation(.automatic(tool: 2))
        #expect(!flow.calibrationSent)
    }

    @Test func theLastStepHasNoNext() {
        var flow = BitChangeFlow(sourceLine: 8)
        flow.advance(machine: .ready)
        flow.calibrationSent = true
        flow.advance(machine: .ready)
        #expect(flow.step == .restart)
        let advancedPastTheEnd = flow.advance(machine: .ready)
        #expect(!advancedPastTheEnd)
        #expect(flow.blocker(machine: .ready) == nil)
    }

    @Test func goingBackStopsAtTheFirstStep() {
        var flow = BitChangeFlow(sourceLine: 8)
        flow.advance(machine: .ready)
        flow.goBack()
        #expect(flow.step == .secure)
        flow.goBack()
        #expect(flow.step == .secure)
    }

    // MARK: Result

    @Test func aBitReplacedByHandDoesNotRepeatTheToolChange() {
        let options = BitChangeFlow(sourceLine: 8).resumeOptions()
        #expect(!options.includeToolChange)
    }

    @Test func anAutomaticChangeUsesTheChosenTool() {
        var flow = BitChangeFlow(sourceLine: 5)
        flow.setInstallation(.automatic(tool: 3))
        let options = flow.resumeOptions()
        #expect(options.includeToolChange)
        #expect(options.toolOverride == 3)

        let (state, maxZ) = GCodeModalState.scan(lines: program, beforeLine: 5)
        let preamble = ResumePreambleBuilder.build(state: state, maxZ: maxZ, resumeLine: 5, options: options)
        #expect(preamble.lines.contains("M6 T3"))
    }

    @Test func choosesTheRestartLine() {
        var flow = BitChangeFlow(sourceLine: 8)
        let resolver = resolver()

        flow.restart = .passStart
        #expect(flow.resumePoint(using: resolver).line == 4)

        flow.restart = .backUp(millimeters: 15)
        #expect(flow.resumePoint(using: resolver).line == 6)

        flow.restart = .exactLine
        let exact = flow.resumePoint(using: resolver)
        #expect(exact.line == 8)
        #expect(exact.reason == .chosen)
    }
}
