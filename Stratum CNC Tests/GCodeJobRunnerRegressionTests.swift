import Testing
@testable import Stratum_CNC

struct GCodeJobRunnerRegressionTests {
    @Test @MainActor func leadingCommentsDoNotDiscardMotionCommands() {
        let runner = GCodeJobRunner()
        var sent: [String] = []
        runner.configure { sent.append($0) }
        runner.start(lines: ["(comment only)", "; comment", "(move) G1 X1 ; cut", "G1 (next) X2"])
        #expect(sent == ["G1 X1"])
        runner.handleMachineLine("ok")
        #expect(sent == ["G1 X1", "G1  X2"])
        runner.handleMachineLine("ok")
        #expect(runner.state == .completed)
        #expect(runner.totalLines == 2)
    }

    @Test @MainActor func unrelatedTextDoesNotAcknowledgeCommands() {
        let runner = GCodeJobRunner()
        var sent: [String] = []
        runner.configure { sent.append($0) }
        runner.start(lines: ["G1 X1", "G1 X2"])
        runner.handleMachineLine("looking for probe")
        #expect(sent == ["G1 X1"])
        runner.pause()
        runner.handleMachineLine("ok")
        runner.handleMachineLine("ok")
        #expect(sent == ["G1 X1"])
        runner.resume()
        #expect(sent == ["G1 X1", "G1 X2"])
        runner.handleMachineLine("ok")
        #expect(runner.state == .completed)
    }

    @Test(arguments: ["error: Probe failed", "ALARM: Probe failed"])
    @MainActor func failedCommandsAbortTheMacro(response: String) {
        let runner = GCodeJobRunner()
        var sent: [String] = []
        var finished = false
        var failed = false
        runner.configure { sent.append($0) }
        runner.onFinish = { finished = true }
        runner.onFailure = { failed = true }
        runner.start(lines: ["G38.2 Z-10 F50", "G10L20P0Z0"])
        runner.handleMachineLine(response)
        runner.handleMachineLine("ok")
        #expect(runner.state == .failed(response))
        #expect(sent == ["G38.2 Z-10 F50"])
        #expect(!finished)
        #expect(failed)
    }
}
