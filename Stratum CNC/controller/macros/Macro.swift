//
//  Macro.swift
//  Stratum CNC
//
//  Built-in parametric macros. A macro is a name, a few numeric parameters
//  and a generator that turns the parameter values into G-code lines.
//

import Foundation

struct MacroParameter: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let unit: String
    let defaultValue: Double
}

struct MacroError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Macro: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let systemImage: String
    let parameters: [MacroParameter]
    /// Parameter values (keyed by `MacroParameter.id`) in, G-code lines out.
    let generate: @Sendable ([String: Double]) -> Result<[String], MacroError>
}

// MARK: - Formatting

enum GCodeNumber {
    /// Up to 3 decimals, trailing zeros trimmed: `2.000` -> `2`, `-0.500` -> `-0.5`.
    static func string(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return (text == "-0" || text.isEmpty) ? "0" : text
    }
}

private func n(_ value: Double) -> String { GCodeNumber.string(value) }

// MARK: - Built-in macros

extension Macro {

    static let builtIn: [Macro] = [peckDrilling, threadMillM1_6]

    /// Drills at the current X/Y. Z0 is the work surface. Every peck goes
    /// down by `peck`, then retracts fully to clear the chips, rapids back to
    /// just above the previous depth and continues at feed.
    static let peckDrilling = Macro(
        id: "peck-drilling",
        name: "Peck Drilling",
        summary: "Drills at the current X/Y (Z0 = work surface). Retracts fully after each peck to clear chips.",
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

            guard depth > 0 else { return .failure(.init("Hole depth must be greater than 0.")) }
            guard peck > 0 else { return .failure(.init("Peck depth must be greater than 0.")) }
            guard retract >= 0 else { return .failure(.init("Retract height can't be negative.")) }
            guard gap >= 0 else { return .failure(.init("Re-entry gap can't be negative.")) }
            guard feed > 0 else { return .failure(.init("Plunge feed must be greater than 0.")) }
            guard rpm >= 0 else { return .failure(.init("Spindle speed can't be negative.")) }
            guard depth / peck <= 500 else { return .failure(.init("Too many pecks (max 500).")) }

            var lines = [
                "(Peck drilling: depth \(n(depth)), peck \(n(peck)))",
                "G21",
                "G90",
                "G94"
            ]
            if rpm > 0 { lines.append("M3 S\(Int(rpm))") }
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

            if rpm > 0 { lines.append("M5") }
            return .success(lines)
        }
    )

    /// M1.6 x 0.35 internal thread, right-hand, single-point helical thread
    /// milling at the current X/Y (the hole centre), Z0 = work surface.
    /// Climb milling: spindle CW (M3) + CCW helix (G3) climbing from the
    /// bottom of the thread upwards.
    ///
    /// Everything is relative in XY (G91) because the hole centre is wherever
    /// the tool currently is; Z moves are absolute (G90).
    static let threadMillM1_6 = Macro(
        id: "thread-mill-m1.6",
        name: "Thread Mill M1.6",
        summary: "M1.6 × 0.35, right-hand, internal. Pre-drill ⌀1.25 mm. Tool must be centred over the hole, Z0 = surface.",
        systemImage: "screwdriver",
        parameters: [
            .init(id: "depth", label: "Thread length", unit: "mm", defaultValue: 3),
            .init(id: "cutter", label: "Cutter diameter", unit: "mm", defaultValue: 1.0),
            .init(id: "feed", label: "Feed", unit: "mm/min", defaultValue: 40),
            .init(id: "safe", label: "Safe height", unit: "mm", defaultValue: 2),
            .init(id: "rpm", label: "Spindle (0 = as is)", unit: "rpm", defaultValue: 12000)
        ],
        generate: { values in
            let major = 1.6
            let pitch = 0.35
            let pilot = 1.25

            let depth = values["depth"] ?? 0
            let cutter = values["cutter"] ?? 0
            let feed = values["feed"] ?? 0
            let safe = values["safe"] ?? 0
            let rpm = values["rpm"] ?? 0

            guard depth > 0 else { return .failure(.init("Thread length must be greater than 0.")) }
            guard cutter > 0 else { return .failure(.init("Cutter diameter must be greater than 0.")) }
            guard cutter < pilot else { return .failure(.init("Cutter must be smaller than the ⌀\(n(pilot)) pilot hole.")) }
            guard cutter < major else { return .failure(.init("Cutter must be smaller than the thread.")) }
            guard feed > 0 else { return .failure(.init("Feed must be greater than 0.")) }
            guard safe >= 0 else { return .failure(.init("Safe height can't be negative.")) }
            guard rpm >= 0 else { return .failure(.init("Spindle speed can't be negative.")) }

            // Radius of the cutter's centre path around the hole centre.
            let radius = (major - cutter) / 2
            // Whole turns only; the last one may end slightly above the surface (in air).
            let turns = Int((depth / pitch).rounded(.up))

            var lines = [
                "(Thread mill M1.6x0.35 internal RH, length \(n(depth)), cutter \(n(cutter)))",
                "G21",
                "G90",
                "G94"
            ]
            if rpm > 0 { lines.append("M3 S\(Int(rpm))") }
            lines.append("G0 Z\(n(safe))")
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

            lines.append("G0 Z\(n(safe))")
            if rpm > 0 { lines.append("M5") }
            return .success(lines)
        }
    )
}
