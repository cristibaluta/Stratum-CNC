//
//  ToolpathGCodeBuilder.swift
//  Stratum CNC
//
//  Turns the toolpaths the user generated in CAM into a G-code program, using
//  StratumCAM's `SCGCodeEngine`.
//
//  Two steps, so the slow part can run off the main thread:
//    1. `plan(toolpaths:generations:)` — cheap. Decides which toolpaths are ready to be
//       posted and which are not (and why). Reads CAM state, so call it on the main actor.
//    2. `generate(_:)` — the engine run. Touches no shared state; safe on any thread.
//

import Foundation
import StratumCAM

enum ToolpathGCodeBuilder {

    /// One toolpath, ready to go through the G-code engine. It keeps the settings the toolpath
    /// was generated with (feed, plunge, spindle speed, safe heights…) because those differ
    /// from one toolpath to the next, and the engine takes a single `MachineSettings` per call.
    ///
    /// `@unchecked Sendable`: same reasoning as `ComputedGeneration` in CAMModel. The engine
    /// output is never mutated after it's generated.
    struct Section: @unchecked Sendable {
        let name: String
        let outputs: [SC.OutputToolpath]
        let settings: SC.MachineSettings
    }

    /// A toolpath left out of the program, and what the user has to do about it.
    struct Skipped {
        let name: String
        let reason: String
    }

    struct Plan {
        /// In the same order as the toolpath list in CAM.
        var sections: [Section] = []
        var skipped: [Skipped] = []
        /// How many toolpaths the project has, whether they made it into `sections` or not.
        var totalCount = 0

        /// Why nothing can be generated. Only meaningful when `sections` is empty.
        var nothingToGenerateMessage: String {
            if totalCount == 0 {
                return "This project has no toolpaths yet. In CAM, add a toolpath, select its shapes and press Generate."
            }
            return "None of the toolpaths is ready to become G-code:\n\n" + Self.bulletList(skipped)
        }

        /// Shown after a successful run that still had to leave some toolpaths out.
        var partialMessage: String {
            "G-code was generated from \(sections.count) of \(totalCount) toolpaths. Not included:\n\n"
                + Self.bulletList(skipped)
        }

        private static func bulletList(_ skipped: [Skipped]) -> String {
            skipped.map { "• \($0.name): \($0.reason)" }.joined(separator: "\n")
        }
    }

    // MARK: Step 1 — what can be posted

    /// Only a toolpath whose last "Generate" succeeded *and* still matches its current settings
    /// and shapes goes into the program. That is exactly what the preview in CAM shows, so the
    /// G-code can never disagree with what the user looked at. Anything else is reported, not
    /// silently dropped — a missing toolpath in a CNC job should never be a surprise.
    static func plan(toolpaths: [ToolpathData], generations: [UUID: ToolpathGeneration]) -> Plan {

        var plan = Plan(totalCount: toolpaths.count)

        for toolpath in toolpaths {
            guard !toolpath.targets.isEmpty else {
                plan.skipped.append(Skipped(name: toolpath.name, reason: "no shapes selected."))
                continue
            }
            guard let generation = generations[toolpath.id] else {
                plan.skipped.append(Skipped(name: toolpath.name, reason: "not generated yet. Press Generate in CAM."))
                continue
            }
            switch generation.outcome {
            case .failure:
                let detail = generation.errorMessage ?? "unknown error."
                plan.skipped.append(Skipped(name: toolpath.name, reason: "generation failed. \(detail)"))

            case .success(let outputs):
                guard generation.isCurrent(for: toolpath) else {
                    plan.skipped.append(Skipped(name: toolpath.name,
                                                reason: "changed since it was generated. Press Generate in CAM again."))
                    continue
                }
                guard generation.passCount > 0 else {
                    plan.skipped.append(Skipped(name: toolpath.name, reason: "it has no cutting passes."))
                    continue
                }
                plan.sections.append(Section(name: toolpath.name,
                                             outputs: outputs,
                                             settings: ToolpathGenerator.makeSettings(from: generation.source)))
            }
        }
        return plan
    }

    // MARK: Step 2 — the engine run

    /// One `SCGCodeEngine.generateGCode` call per toolpath, each with its own settings, joined
    /// in order into a single program.
    static func generate(_ sections: [Section]) -> String {

        let engine = SCGCodeEngine()

        let programs = sections.map { section -> String in
            let gcode = engine.generateGCode(from: section.outputs, settings: section.settings)
            return gcode.trimmingCharacters(in: .newlines)
        }
        .filter { !$0.isEmpty }

        guard !programs.isEmpty else {
            return ""
        }
        return programs.joined(separator: "\n") + "\n"
    }
}
