//
//  MakeraHeaderParser.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import Foundation

/// Parses the `;@MKR|…` block Makera Studio writes at the top of its
/// programs:
///
///     ;@MKR|BEGIN
///     ;@MKR|TOOL|number=4|name=3.175*2*8mm Flat End(Metal)|type=Flat End|diameter=2|...
///     ;@MKR|END
///
/// Each line is `;@MKR|<RECORD>|key=value|key=value…`. Only `TOOL` records
/// are read for now; everything else is skipped. Not a Makera file (no
/// `BEGIN`) → `nil`.
struct MakeraHeaderParser: GCodeHeaderParser {

    private static let linePrefix = ";@MKR|"

    /// The header doesn't say how many flutes a tool has, and `ToolSpec`
    /// requires a number. Nothing in the heightmap carve reads it today.
    private static let assumedFlutes = 2

    func parse(headerLines: [String]) -> GCodeHeader? {
        var sawBegin = false
        var tools: [Int: ToolSpec] = [:]

        for rawLine in headerLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(Self.linePrefix) else {
                continue
            }
            let fields = line.dropFirst(Self.linePrefix.count)
                .split(separator: "|", omittingEmptySubsequences: false)
            guard let record = fields.first else {
                continue
            }

            switch record {
            case "BEGIN":
                sawBegin = true
            case "END":
                return sawBegin ? GCodeHeader(tools: tools) : nil
            case "TOOL":
                guard sawBegin,
                      let (number, spec) = Self.tool(from: Self.keyValues(fields.dropFirst())),
                      tools[number] == nil else {
                    continue
                }
                tools[number] = spec
            default:
                break
            }
        }

        // No END line (truncated header) — still usable if it began properly.
        return sawBegin ? GCodeHeader(tools: tools) : nil
    }

    // MARK: Helpers

    private static func keyValues(_ fields: ArraySlice<Substring>) -> [String: String] {
        var result: [String: String] = [:]
        for field in fields {
            guard let equals = field.firstIndex(of: "=") else {
                continue
            }
            result[String(field[..<equals])] = String(field[field.index(after: equals)...])
        }
        return result
    }

    /// Builds a `ToolSpec` from one `TOOL` record. `nil` if the number or
    /// diameter is missing, or the tool type isn't one `ToolSpec.Kind` can
    /// represent — that tool just stays "Unassigned" in the picker.
    private static func tool(from values: [String: String]) -> (Int, ToolSpec)? {
        guard let number = values["number"].flatMap({ Int($0) }),
              let diameter = values["diameter"].flatMap({ Double($0) }), diameter > 0,
              let kind = kind(forType: values["type"] ?? "") else {
            return nil
        }

        // `diameter` is the cutting diameter; `handlediameter` is the shank.
        var tipAngle: Double?
        if kind == .vBit || kind == .engraver {
            let angle = values["angle"].flatMap { Double($0) } ?? 0
            let halfAngle = values["halfAngle"].flatMap { Double($0) } ?? 0
            tipAngle = angle > 0 ? angle : (halfAngle > 0 ? halfAngle * 2 : nil)
        }

        let name = values["name"].flatMap { $0.isEmpty ? nil : $0 } ?? "T\(number)"

        return (number, ToolSpec(name: name,
                                 diameterMM: diameter,
                                 flutes: assumedFlutes,
                                 kind: kind,
                                 tipAngleDegrees: tipAngle))
    }

    private static func kind(forType type: String) -> ToolSpec.Kind? {
        let t = type.lowercased()
        if t.contains("flat") || t.contains("end mill") {
            return .endMill
        }
        if t.contains("ball") {
            return .ballNose
        }
        if t.contains("v-bit") || t.contains("v bit") || t.contains("vbit") || t.contains("chamfer") {
            return .vBit
        }
        if t.contains("engrav") {
            return .engraver
        }
        if t.contains("drill") {
            return .drill
        }
        return nil
    }
}
