import Foundation
import Testing
@testable import Stratum_CNC

struct JobProgressTests {

    private func makeProgress(totalLines: Int = 1000, playSent: Date? = nil) -> JobProgress {
        var progress = JobProgress(fileName: "part.nc",
                                   fingerprint: "abc",
                                   remotePath: "/sd/gcodes/part.nc",
                                   originX: 10,
                                   originY: 20,
                                   totalLines: totalLines,
                                   now: Date(timeIntervalSince1970: 0))
        if let playSent { progress.markPlaySent(at: playSent) }
        return progress
    }

    private func position(_ line: Int, _ percent: Int) -> JobProgress.Position {
        .init(line: line, percent: percent)
    }

    @Test func startingBecomesRunningOnlyWithAnActiveJob() {
        var progress = makeProgress()
        // Probing moves report Run but no active job yet.
        #expect(progress.observe(machineState: "Run", active: nil, frozen: nil) == .unchanged)
        #expect(progress.phase == .starting)

        #expect(progress.observe(machineState: "Run", active: position(5, 1), frozen: nil) == .changed)
        #expect(progress.phase == .running)
        #expect(progress.lastLine == 5)
    }

    @Test func tracksHoldAndSuspend() {
        var progress = makeProgress()
        _ = progress.observe(machineState: "Run", active: position(10, 2), frozen: nil)

        #expect(progress.observe(machineState: "Hold:0", active: position(12, 2), frozen: nil) == .changed)
        #expect(progress.phase == .held)
        #expect(progress.observe(machineState: "Pause", active: position(12, 2), frozen: nil) == .changed)
        #expect(progress.phase == .suspended)
        #expect(progress.lastLine == 12)
    }

    @Test func lineNeverGoesBackward() {
        var progress = makeProgress()
        _ = progress.observe(machineState: "Run", active: position(50, 5), frozen: nil)
        _ = progress.observe(machineState: "Run", active: position(40, 4), frozen: nil)
        #expect(progress.lastLine == 50)
        #expect(progress.percent == 5)
    }

    @Test func unchangedReportDoesNotCountAsChange() {
        var progress = makeProgress()
        _ = progress.observe(machineState: "Run", active: position(50, 5), frozen: nil)
        #expect(progress.observe(machineState: "Run", active: position(50, 5), frozen: nil) == .unchanged)
    }

    @Test func alarmKeepsTheLine() {
        var progress = makeProgress()
        _ = progress.observe(machineState: "Run", active: position(300, 30), frozen: nil)
        #expect(progress.observe(machineState: "Alarm", active: nil, frozen: position(300, 30)) == .changed)
        #expect(progress.phase == .alarm)
        #expect(progress.lastLine == 300)
        // Unlocking later doesn't erase it.
        #expect(progress.observe(machineState: "Idle", active: nil, frozen: position(300, 30)) == .unchanged)
        #expect(progress.isResumable)
    }

    @Test func idleAtOneHundredPercentCompletes() {
        var progress = makeProgress()
        _ = progress.observe(machineState: "Run", active: position(990, 99), frozen: nil)
        #expect(progress.observe(machineState: "Idle", active: nil, frozen: position(998, 100)) == .completed)
    }

    @Test func idleBeforeTheEndIsInterrupted() {
        var progress = makeProgress()
        _ = progress.observe(machineState: "Run", active: position(400, 40), frozen: nil)
        #expect(progress.observe(machineState: "Idle", active: nil, frozen: position(410, 41)) == .changed)
        #expect(progress.phase == .interrupted)
        #expect(progress.lastLine == 410)
    }

    @Test func startingIsDiscardedWhenIdleLongAfterPlay() {
        let sent = Date(timeIntervalSince1970: 100)
        var progress = makeProgress(playSent: sent)
        #expect(progress.observe(machineState: "Idle", active: nil, frozen: nil,
                                 now: sent.addingTimeInterval(5)) == .unchanged)
        #expect(progress.observe(machineState: "Idle", active: nil, frozen: nil,
                                 now: sent.addingTimeInterval(60)) == .discarded)
    }

    @Test func startingWithoutPlaySentIsNeverDiscardedByIdle() {
        var progress = makeProgress()
        #expect(progress.observe(machineState: "Idle", active: nil, frozen: nil,
                                 now: Date(timeIntervalSince1970: 100_000)) == .unchanged)
    }

    @Test func stoppedJobStaysResumable() {
        var progress = makeProgress()
        _ = progress.observe(machineState: "Run", active: position(200, 20), frozen: nil)
        progress.markStopped()
        #expect(progress.phase == .stopped)
        #expect(progress.isResumable)
        #expect(progress.observe(machineState: "Idle", active: nil, frozen: position(200, 20)) == .unchanged)
    }

    @Test func fingerprintMatching() {
        let progress = makeProgress()
        #expect(progress.matches(fingerprint: "abc"))
        #expect(!progress.matches(fingerprint: "other"))
    }

    @Test func storeRoundTripsAndClears() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JobProgressStore(fileURL: directory.appendingPathComponent("job-progress.json"))
        #expect(store.load() == nil)

        var progress = makeProgress()
        _ = progress.observe(machineState: "Pause", active: position(77, 7), frozen: nil)
        store.save(progress)

        let loaded = try #require(store.load())
        #expect(loaded.phase == .suspended)
        #expect(loaded.lastLine == 77)
        #expect(loaded.fingerprint == "abc")
        #expect(loaded.originX == 10 && loaded.originY == 20)

        store.clear()
        #expect(store.load() == nil)
    }
}
