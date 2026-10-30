//
//  BitChangeFlow.swift
//  Stratum CNC
//
//  The steps of changing a bit in the middle of a job and carrying on:
//  secure the machine, replace the bit, choose where to restart. Pure state
//  and rules; `BitChangeSheet` presents it and talks to the machine.
//
//  The flow always ends by resuming with a generated file (`ResumeFileBuilder`)
//  rather than by `goto` on a suspended job. The machine has to be stopped and
//  unlocked first, which is what makes the end state certain: whatever the bit
//  change did to the spindle, tool and Z, the resume file sets the state again.
//

import Foundation

struct BitChangeFlow: Equatable {

    enum Step: Int, CaseIterable, Equatable {
        case secure
        case replace
        case restart

        var title: String {
            switch self {
            case .secure: return "Stop"
            case .replace: return "Replace bit"
            case .restart: return "Restart"
            }
        }
    }

    /// How the new bit gets into the spindle.
    enum Installation: Equatable {
        /// Loosen the collet, swap the bit, tighten it, measure its length
        /// (`M490.2`, `M490.1`, `M491`). The program's own tool change is not
        /// repeated: the bit already is in the spindle.
        case byHand
        /// The automatic tool changer fetches this tool (`M6 T<n>`) as the first
        /// thing the resume does; the machine measures it as part of the change.
        case automatic(tool: Int)
    }

    enum Restart: Equatable {
        /// The start of the pass that was interrupted.
        case passStart
        /// A little before where it stopped, but not before the pass start.
        case backUp(millimeters: Double)
        /// Exactly the given line.
        case exactLine
    }

    /// What the machine is doing, as far as the flow cares.
    enum MachineCondition: Equatable {
        /// No status report.
        case unknown
        /// Running or in a feed hold: the spindle may be turning.
        case moving
        /// Suspended by `suspend`: needs a stop before the file can be resumed.
        case suspended
        /// Alarm: needs unlocking.
        case alarm
        /// Idle: safe to work on.
        case ready

        init(machineState: String?) {
            let base = machineState?.split(separator: ":").first.map(String.init) ?? ""
            switch base {
            case "Run", "Hold", "Jog", "Home", "Door": self = .moving
            case "Pause": self = .suspended
            case "Alarm": self = .alarm
            case "Idle": self = .ready
            default: self = .unknown
            }
        }
    }

    static let defaultBackUpMillimeters = 5.0

    var step: Step = .secure
    var installation: Installation = .byHand
    var restart: Restart = .passStart
    /// Where the job stopped, in the original program (1-based).
    var sourceLine: Int
    /// The tool length measurement (`M491`) was started after replacing by hand.
    var calibrationSent = false
    /// Probe the work Z again when starting (`autoZBeforeRun`), for when the new
    /// bit can't be trusted to be measured relative to the old one.
    var reprobeZ = false

    init(sourceLine: Int) {
        self.sourceLine = max(1, sourceLine)
    }

    // MARK: Gating

    /// Whether the current step is done and the next one may start.
    func canAdvance(machine: MachineCondition) -> Bool {
        switch step {
        case .secure:
            return machine == .ready
        case .replace:
            guard machine == .ready else { return false }
            switch installation {
            case .byHand: return calibrationSent
            case .automatic(let tool): return tool >= 1
            }
        case .restart:
            return false
        }
    }

    /// Why the current step can't be left yet, for the sheet.
    func blocker(machine: MachineCondition) -> String? {
        guard !canAdvance(machine: machine), step != .restart else { return nil }
        switch step {
        case .secure:
            switch machine {
            case .ready: return nil
            case .moving: return "The machine is still moving. Stop the job first."
            case .suspended: return "The job is suspended on the machine. Stop it to continue."
            case .alarm: return "The machine is in alarm. Unlock it to continue."
            case .unknown: return "Waiting for the machine's status."
            }
        case .replace:
            if machine != .ready { return "Wait until the machine is idle." }
            switch installation {
            case .byHand: return "Measure the new bit's length once it is tightened."
            case .automatic: return "Enter the tool number (1 or higher)."
            }
        case .restart:
            return nil
        }
    }

    @discardableResult
    mutating func advance(machine: MachineCondition) -> Bool {
        guard canAdvance(machine: machine), let next = Step(rawValue: step.rawValue + 1) else { return false }
        step = next
        return true
    }

    mutating func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    mutating func setInstallation(_ installation: Installation) {
        guard installation != self.installation else { return }
        self.installation = installation
        calibrationSent = false
    }

    // MARK: Result

    /// The preamble settings for the chosen installation.
    func resumeOptions(base: ResumeOptions = ResumeOptions()) -> ResumeOptions {
        var options = base
        switch installation {
        case .byHand:
            options.includeToolChange = false
            options.toolOverride = nil
        case .automatic(let tool):
            options.includeToolChange = true
            options.toolOverride = tool
        }
        return options
    }

    /// The line to resume from for the chosen restart.
    func resumePoint(using resolver: ResumePointResolver) -> ResumePoint {
        switch restart {
        case .passStart:
            return resolver.resolve(requestedLine: sourceLine)
        case .backUp(let millimeters):
            return resolver.backedUp(from: sourceLine, millimeters: millimeters)
        case .exactLine:
            let line = min(max(1, sourceLine), max(1, resolver.lineCount))
            return ResumePoint(requestedLine: line, line: line, reason: .chosen)
        }
    }
}
