//
//  Macro.swift
//  Stratum CNC
//
//  Built-in parametric macros. A macro is a name, a few numeric parameters
//  and a generator that turns the parameter values into G-code lines.
//

import Foundation
import StratumCAM

struct MacroParameter: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let unit: String
    let defaultValue: Double
}

struct MacroError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) {
        self.message = message
    }
    var errorDescription: String? {
        message
    }
}

/// One thing the person must confirm before a macro runs.
struct MacroCheck: Hashable, Sendable {
    let text: String
    /// Adds a "Probe…" button to the item, for what only probing can set.
    var offersProbe = false

    /// What every macro asks, unless it has its own list: the tool, Z (probing sets the tool
    /// length and Z0 together) and where the hole is.
    static let standard: [MacroCheck] = [
        MacroCheck(text: "The tool is fitted and clamped"),
        MacroCheck(text: "Z is probed: the tool length is known and Z0 is the top of the stock",
                   offersProbe: true),
        MacroCheck(text: "The centre of the hole is at the X/Y shown in the macro")
    ]
}

/// One entry of a macro's preset picker: picking it sets these parameters (keyed by
/// `MacroParameter.id`) at once. The parameters stay editable; the picker just shows the preset
/// the values match, or "Custom".
struct MacroPreset: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let values: [String: Double]
}

struct Macro: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let systemImage: String
    let parameters: [MacroParameter]
    /// Parameter values (keyed by `MacroParameter.id`) in, G-code lines out.
    let generate: @Sendable ([String: Double]) -> Result<[String], MacroError>
    /// What the person must confirm, one tick each, before "Review & Start" lets the macro run.
    /// The same for every macro unless it sets its own. Empty: nothing to confirm.
    var checklist: [MacroCheck] = MacroCheck.standard
    /// Label of the preset picker above the parameters.
    var presetLabel: String = "Preset"
    /// Empty: no picker.
    var presets: [MacroPreset] = []
}

// MARK: - Formatting

enum GCodeNumber {
    /// Up to 3 decimals, trailing zeros trimmed: `2.000` -> `2`, `-0.500` -> `-0.5`.
    static func string(_ value: Double) -> String {
        value.trimmedString()
    }
}

private func n(_ value: Double) -> String {
    GCodeNumber.string(value)
}

/// First move of a macro that was given a position: a rapid to the hole's X/Y, in work
/// coordinates. `MacroStore` adds the position to the parameter values under `Macro.xKey` /
/// `Macro.yKey` only when "Go to position" is ticked. Without it there is no move: the macro runs
/// where the tool is.
private func rapidToHole(_ values: [String: Double]) -> String? {
    guard let x = values[Macro.xKey], let y = values[Macro.yKey] else {
        return nil
    }
    return "G0 X\(n(x)) Y\(n(y))"
}

// MARK: - Built-in macros

extension Macro {

    /// Keys of the hole position in the values handed to `generate`. Not `MacroParameter`s: the
    /// position is shared by all macros and edited in the X/Y fields, not in the parameter grid.
    static let xKey = "x"
    static let yKey = "y"

    static let builtIn: [Macro] = [peckDrilling, threadMill]

    /// Drills at the tool's X/Y, or at the position set. Z0 is the work surface. Every peck goes
    /// down by `peck`, then retracts fully to clear the chips, rapids back to
    /// just above the previous depth and continues at feed.
    static let peckDrilling = Macro(
        id: "peck-drilling",
        name: "Peck Drilling",
        summary: "Drills at the tool's X/Y, or at the position set (Z0 = work surface). Retracts fully after each peck to clear chips.",
        systemImage: "arrow.down.to.line",
        parameters: [
            .init(id: "depth", label: "Hole depth", unit: "mm", defaultValue: 5),
            .init(id: "peck", label: "Peck depth", unit: "mm", defaultValue: 1),
            .init(id: "retract", label: "Retract height", unit: "mm", defaultValue: 2),
            .init(id: "gap", label: "Re-entry gap", unit: "mm", defaultValue: 0.5),
            .init(id: "feed", label: "Plunge feed", unit: "mm/min", defaultValue: 100),
            .init(id: "rpm", label: "Spindle (0 = as is)", unit: "rpm", defaultValue: 10000)
        ],
        generate: { values in
            let depth = values["depth"] ?? 0
            let peck = values["peck"] ?? 0
            let retract = values["retract"] ?? 0
            let gap = values["gap"] ?? 0
            let feed = values["feed"] ?? 0
            let rpm = values["rpm"] ?? 0

            guard depth > 0 else {
                return .failure(.init("Hole depth must be greater than 0."))
            }
            guard peck > 0 else {
                return .failure(.init("Peck depth must be greater than 0."))
            }
            guard retract >= 0 else {
                return .failure(.init("Retract height can't be negative."))
            }
            guard gap >= 0 else {
                return .failure(.init("Re-entry gap can't be negative."))
            }
            guard feed > 0 else {
                return .failure(.init("Plunge feed must be greater than 0."))
            }
            guard rpm >= 0 else {
                return .failure(.init("Spindle speed can't be negative."))
            }
            guard depth / peck <= 500 else {
                return .failure(.init("Too many pecks (max 500)."))
            }

            var lines = [
                "(Peck drilling: depth \(n(depth)), peck \(n(peck)))",
                "G21",
                "G90",
                "G94"
            ]
            if let move = rapidToHole(values) {
                lines.append(move)
            }
            if rpm > 0 {
                lines.append("M3 S\(Int(rpm))")
            }
            lines.append("G0 Z\(n(retract))")

            var previous = 0.0
            while previous < depth - 1e-9 {
                let target = min(previous + peck, depth)
                // Rapid to just above where the last peck ended (never above the retract height).
                let approach = min(-previous + gap, retract)
                lines.append("G0 Z\(n(approach))")
                lines.append("G1 Z\(n(-target)) F\(n(feed))")
                lines.append("G0 Z\(n(retract))")
                previous = target
            }

            if rpm > 0 {
                lines.append("M5")
            }
            return .success(lines)
        }
    )

    /// Internal right-hand thread, single-point helical thread milling at the tool's X/Y (the hole
    /// centre) or at the position set, Z0 = work surface. The thread comes from the
    /// standard-thread picker (the same list as the CAM thread mill operation) or from the
    /// diameter and pitch typed in.
    /// Climb milling: spindle CW (M3) + CCW helix (G3) climbing from the
    /// bottom of the thread upwards.
    ///
    /// The thread is cut in `passes` laps, each with the cutter's path wider than the last: the
    /// first just touches the pre-drilled hole (diameter - pitch), the last lands exactly on the
    /// thread diameter. Every lap is a full climb from the bottom.
    ///
    /// Everything in XY is relative (G91) from the hole centre, wherever the tool is (or the
    /// rapid to the position set put it); Z moves are absolute (G90).
    static let threadMill = Macro(
        id: "thread-mill",
        name: "Thread Mill",
        summary: "Internal, right-hand. Pre-drill the hole to about diameter − pitch (M1.6: ⌀1.25 mm). Runs at the tool's X/Y (the hole centre), or at the position set. Z0 = surface.",
        systemImage: "screwdriver",
        parameters: [
            .init(id: "major", label: "Thread diameter", unit: "mm", defaultValue: 1.6),
            .init(id: "pitch", label: "Pitch", unit: "mm", defaultValue: 0.35),
            .init(id: "passes", label: "Passes", unit: "", defaultValue: 1),
            .init(id: "depth", label: "Thread length", unit: "mm", defaultValue: 3),
            .init(id: "cutter", label: "Cutter diameter", unit: "mm", defaultValue: 1.0),
            .init(id: "feed", label: "Feed", unit: "mm/min", defaultValue: 40),
            .init(id: "safe", label: "Safe height", unit: "mm", defaultValue: 2),
            .init(id: "rpm", label: "Spindle (0 = as is)", unit: "rpm", defaultValue: 12000)
        ],
        generate: { values in
            let major = values["major"] ?? 0
            let pitch = values["pitch"] ?? 0
            let passes = Int((values["passes"] ?? 0).rounded())
            let depth = values["depth"] ?? 0
            let cutter = values["cutter"] ?? 0
            let feed = values["feed"] ?? 0
            let safe = values["safe"] ?? 0
            let rpm = values["rpm"] ?? 0

            guard major > 0 else {
                return .failure(.init("Thread diameter must be greater than 0."))
            }
            guard pitch > 0 else {
                return .failure(.init("Pitch must be greater than 0."))
            }
            guard pitch < major else {
                return .failure(.init("Pitch must be smaller than the thread diameter."))
            }
            guard (1...10).contains(passes) else {
                return .failure(.init("Passes must be between 1 and 10."))
            }
            guard depth > 0 else {
                return .failure(.init("Thread length must be greater than 0."))
            }
            guard cutter > 0 else {
                return .failure(.init("Cutter diameter must be greater than 0."))
            }
            // The hole the thread is cut in: the standard tap-drill size
            let pilot = major - pitch
            guard cutter < pilot else {
                return .failure(.init("Cutter must be smaller than the ⌀\(n(pilot)) pilot hole."))
            }
            guard feed > 0 else {
                return .failure(.init("Feed must be greater than 0."))
            }
            guard safe >= 0 else {
                return .failure(.init("Safe height can't be negative."))
            }
            guard rpm >= 0 else {
                return .failure(.init("Spindle speed can't be negative."))
            }

            // Radius of the cutter's centre path around the hole centre: from just touching the
            // pilot hole to the full thread, in equal steps, the last one exact.
            let firstRadius = (pilot - cutter) / 2
            let finalRadius = (major - cutter) / 2
            // Whole turns only; the last one may end slightly above the surface (in air).
            let turns = Int((depth / pitch).rounded(.up))

            var lines = [
                "(Thread mill M\(n(major))x\(n(pitch)) internal RH, length \(n(depth)), cutter \(n(cutter)), \(passes) pass\(passes == 1 ? "" : "es"))",
                "G21",
                "G90",
                "G94"
            ]
            if let move = rapidToHole(values) {
                lines.append(move)
            }
            if rpm > 0 {
                lines.append("M3 S\(Int(rpm))")
            }
            lines.append("G0 Z\(n(safe))")

            for pass in 1...passes {
                let radius = firstRadius + (finalRadius - firstRadius) * Double(pass) / Double(passes)
                if passes > 1 {
                    lines.append("(Pass \(pass)/\(passes): path radius \(n(radius)))")
                }
                // Down to the bottom at the hole centre: the cutter is inside the pilot hole there
                lines.append("G1 Z\(n(-depth)) F\(n(feed))")

                lines.append("G91")
                // Tangential half-circle lead-in from the centre out to the thread radius.
                lines.append("G3 X\(n(radius)) Y0 I\(n(radius / 2)) J0 F\(n(feed))")
                // One full helical turn per pitch, climbing.
                for _ in 0..<turns {
                    lines.append("G3 X0 Y0 Z\(n(pitch)) I\(n(-radius)) J0")
                }
                // Half-circle lead-out back to the centre.
                lines.append("G3 X\(n(-radius)) Y0 I\(n(-radius / 2)) J0")
                lines.append("G90")
            }

            lines.append("G0 Z\(n(safe))")
            if rpm > 0 {
                lines.append("M5")
            }
            return .success(lines)
        },
        presetLabel: "Standard thread",
        presets: SC.standardThreads.map {
            MacroPreset(id: $0.id, label: $0.designation, values: ["major": $0.diameter, "pitch": $0.pitch])
        }
    )
}
