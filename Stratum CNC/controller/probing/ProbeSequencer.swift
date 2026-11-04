//
//  ProbeSequencer.swift
//  Stratum CNC
//
//  Runs a probing cycle (`ProbeStepPlan`s) on the machine, one step at a time.
//
//  Each step goes through `jobRunner`, which sends a line only after the
//  previous one was acknowledged. That matters for probing: the machine's `ok`
//  for a probe move comes after the probe stopped, so the next line starts
//  from the contact point (the same thing `autoZeroProbe` relies on).
//
//  The runner has one pair of finish/failure hooks and `JobCoordinator` owns
//  it, so this listens through `job.onMacroFinished` / `onMacroFailed`.
//
//  After a step that measures, the machine's position is read from the status
//  report once the machine is Idle. The probe stops on the contact, so that
//  position is the contact point. (If `StratumLink` exposes the probe's own
//  `[PRB:…]` report, reading that would replace `readPosition()`.)
//

import Foundation
import StratumLink

@MainActor
final class ProbeSequencer: ObservableObject {

    enum State: Equatable {
        case idle
        case running
        case finished
        case failed(String)
        case stopped
    }

    enum RowStatus: Equatable {
        case pending
        case running
        case done
        case failed
    }

    struct Row: Identifiable, Equatable {
        let id: Int
        let title: String
        var status: RowStatus = .pending
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var rows: [Row] = []
    /// Machine positions read so far, for the result step.
    @Published private(set) var contacts = ProbeContacts()
    /// True when the last run only logged its lines.
    @Published private(set) var wasDryRun = false
    /// The work origin (X, Y) on the machine just before the cycle began:
    /// machine position minus work position. Kept so Apply can be undone.
    /// A stale G92 shift would show up in it too.
    private(set) var originBeforeRun: SIMD2<Double>?

    private let model: ControllerModel
    private var task: Task<Void, Never>?
    private var pending: CheckedContinuation<Bool, Never>?

    init(model: ControllerModel) {
        self.model = model
    }

    var isRunning: Bool { state == .running }

    // MARK: Start / stop

    /// Why a run can't start right now, or nil.
    var startBlocker: String? {
        let connection = model.connection
        guard connection.isConnected else { return "Connect to a machine first." }
        guard let status = connection.status else { return "Waiting for the machine's status." }
        guard status.state.hasPrefix("Idle") else { return "The machine is \(status.state.lowercased()), not idle." }
        if model.jobRunner.isActive { return "Another sequence is running." }
        return nil
    }

    func start(plan: [ProbeStepPlan], dryRun: Bool) {
        guard !isRunning else { return }

        if !dryRun, let blocker = startBlocker {
            state = .failed(blocker)
            return
        }

        rows = plan.enumerated().map { Row(id: $0.offset, title: $0.element.title) }
        contacts = ProbeContacts()
        wasDryRun = dryRun
        originBeforeRun = nil
        if !dryRun, let status = model.connection.status {
            originBeforeRun = SIMD2(Double(status.machinePosition.x) - Double(status.workPosition.x),
                                    Double(status.machinePosition.y) - Double(status.workPosition.y))
        }
        state = .running

        task = Task { await run(plan: plan, dryRun: dryRun) }
    }

    /// Stops the machine and the sequence. Safe to call at any time.
    func stop() {
        guard isRunning else { return }
        task?.cancel()
        model.stopJob()
        resume(false)
        if let index = rows.firstIndex(where: { $0.status == .running }) {
            rows[index].status = .failed
        }
        state = .stopped
        model.connection.appendLog("3D probe: stopped.")
    }

    /// For when the dialog goes away mid-run.
    func stopIfRunning() {
        if isRunning { stop() }
    }

    func reset() {
        guard !isRunning else { return }
        rows = []
        contacts = ProbeContacts()
        state = .idle
    }

    // MARK: Running

    private func run(plan: [ProbeStepPlan], dryRun: Bool) async {
        let log = model.connection

        for (index, step) in plan.enumerated() {
            guard !Task.isCancelled, state == .running else { return }
            rows[index].status = .running

            let lines = step.lines(contacts)

            if dryRun {
                log.appendLog("3D probe (dry run): \(step.title)")
                lines.forEach { log.appendLog("    \($0)") }
                rows[index].status = .done
                continue
            }

            // Comments only means there was nothing to send.
            let toSend = lines.filter { !$0.hasPrefix(";") }
            if !toSend.isEmpty {
                log.appendLog("3D probe: \(step.title)")
                guard await send(toSend) else {
                    await fail(index, step, "The machine reported an error during “\(step.title)”. If a probe move found nothing, the probe did not touch within the search distance. Unlock the machine, then check the probe and try again.")
                    return
                }
            }

            if let key = step.measure {
                guard let position = await readPosition() else {
                    await fail(index, step, "Could not read the machine's position after “\(step.title)”.")
                    return
                }
                contacts[key] = position
                log.appendLog(String(format: "    %@: X %.3f  Y %.3f  Z %.3f (machine)", key, position.x, position.y, position.z))
            }

            if let message = step.check?(contacts) {
                await fail(index, step, message)
                return
            }

            rows[index].status = .done
        }

        guard state == .running else { return }
        state = .finished
        log.appendLog("3D probe: finished.")
    }

    private func fail(_ index: Int, _ step: ProbeStepPlan, _ message: String) async {
        guard state == .running else { return }
        rows[index].status = .failed
        state = .failed(message)
        model.connection.appendLog("3D probe: \(message)")

        // Best effort: get the probe away from the stock, and leave the machine
        // in absolute mode. An alarm may refuse these; that is fine.
        for line in step.recovery + ["G90"] {
            model.sendRawCommand(line)
        }
    }

    // MARK: Talking to the machine

    /// Sends the lines through the job runner and waits until the last one
    /// was acknowledged. False if the runner failed.
    private func send(_ lines: [String]) async -> Bool {
        let job = model.job
        defer {
            job.onMacroFinished = nil
            job.onMacroFailed = nil
        }

        return await withCheckedContinuation { continuation in
            pending = continuation
            job.onMacroFinished = { [weak self] in self?.resume(true) }
            job.onMacroFailed = { [weak self] in self?.resume(false) }
            model.jobRunner.start(lines: lines)
        }
    }

    private func resume(_ result: Bool) {
        guard let continuation = pending else { return }
        pending = nil
        continuation.resume(returning: result)
    }

    /// The machine position in machine coordinates, once it reports Idle.
    /// Asks for a status and gives the answer time to arrive: a report that
    /// was sent before the last move would show the wrong place.
    private func readPosition() async -> SIMD3<Double>? {
        let connection = model.connection
        for _ in 0..<8 {
            guard connection.isConnected, !Task.isCancelled else { return nil }

            connection.requestStatus()
            try? await Task.sleep(nanoseconds: 600_000_000)

            guard let status = connection.status else { continue }
            if status.state.hasPrefix("Alarm") { return nil }
            if status.state.hasPrefix("Idle") {
                return SIMD3(Double(status.machinePosition.x),
                            Double(status.machinePosition.y),
                            Double(status.machinePosition.z))
            }
        }
        return nil
    }
}
