//
//  FusionHeaderParser.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//


//
//  FusionHeaderParser.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import Foundation

/// Parses the tool comments Fusion's post processor writes at the top of a
/// program:
///
///     (T2  M8-1.25 Thread Mill      D=6.35 SD=6. TD=6.35 FL=1.25 ... - ZMIN=-11.156 - thread mill)
///     (T1 D=6. CR=0. - ZMIN=-10. - flat end mill)
///
/// Each is `(T<n> [description] D=<diameter> [CR=…] [TAPER=…deg] … - ZMIN=… - <type>)`.
/// Everything else in Fusion's header (stock, offsets, ...) is skipped. No
/// tool comment found → `nil`.
struct FusionHeaderParser: GCodeHeaderParser {

    /// `(T<number> <rest>)`. Requires digits right after the `T`, so
    /// comments like `(Thread1)` don't match.
    private static let toolLine = try! NSRegularExpression(pattern: #"^\(\s*T(\d+)\b(.*)\)$"#)

    func parse(headerLines: [String]) -> GCodeHeader? {
        var tools: [Int: ToolSpec] = [:]

        for rawLine in headerLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = Self.toolLine.firstMatch(in: line, range: range),
                  let numberRange = Range(match.range(at: 1), in: line),
                  let bodyRange = Range(match.range(at: 2), in: line),
                  let number = Int(line[numberRange]),
                  tools[number] == nil,
                  let spec = Self.tool(number: number, body: String(line[bodyRange])) else {
                continue
            }
            tools[number] = spec
        }

        return tools.isEmpty ? nil : GCodeHeader(tools: tools)
    }

    // MARK: Helpers

    private static func tool(number: Int, body: String) -> ToolSpec? {
        // `D=` is the cutting diameter. `SD=` (shank) and `TD=` don't count —
        // `value(_:in:)` won't match a key that's the tail of a longer word.
        guard let diameter = value("D", in: body), diameter > 0 else {
            return nil
        }

        // Last " - " section is the tool type, unless the line has no type
        // (then it's the `ZMIN=` section, or there's only one section).
        let sections = body.components(separatedBy: " - ")
        let typeText = sections.count > 1
            ? sections.last!.trimmingCharacters(in: .whitespaces)
            : ""
        let type = typeText.hasPrefix("ZMIN") ? "" : typeText

        guard let kind = kind(forType: type) else {
            return nil
        }

        var tipAngle: Double?
        if kind == .vBit || kind == .engraver, let taper = value("TAPER", in: body), taper > 0 {
            // Fusion's taper is measured from the tool axis, i.e. a half angle.
            tipAngle = taper * 2
        }

        return ToolSpec(name: name(number: number, body: body, diameter: diameter, type: type),
                        diameterMM: diameter,
                        flutes: ToolSpec.assumedFlutes,
                        kind: kind,
                        tipAngleDegrees: tipAngle)
    }

    /// The description Fusion puts between `T<n>` and `D=` when the tool has
    /// one ("M8-1.25 Thread Mill"); otherwise "<diameter>mm <type>".
    private static func name(number: Int, body: String, diameter: Double, type: String) -> String {
        if let dRange = body.range(of: #"(?<![A-Za-z])D="#, options: .regularExpression) {
            let description = body[..<dRange.lowerBound]
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if !description.isEmpty {
                return description
            }
        }
        let size = String(format: "%g", diameter) + "mm"
        return type.isEmpty ? "T\(number) \(size)" : "\(size) \(type.capitalized)"
    }

    /// Number after `KEY=`, where KEY isn't the tail of a longer word.
    /// Fusion writes values like `6.` and `0.5`, sometimes with a unit
    /// suffix (`45deg`).
    private static func value(_ key: String, in text: String) -> Double? {
        let pattern = "(?<![A-Za-z])\(key)=(-?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        var number = String(text[range])
        if number.hasSuffix(".") {
            number.removeLast()
        }
        return Double(number)
    }

    /// Fusion's tool-type strings ("flat end mill", "ball end mill",
    /// "thread mill", ...). Anything `ToolSpec.Kind` can't represent → `nil`,
    /// and that tool stays "Unassigned".
    private static func kind(forType type: String) -> ToolSpec.Kind? {
        let t = type.lowercased()
        if t.contains("ball") {
            return .ballNose
        }
        if t.contains("engrav") {
            return .engraver
        }
        if t.contains("chamfer") || t.contains("countersink") || t.contains("counter sink") {
            return .vBit
        }
        if t.contains("drill") {
            return .drill
        }
        // Flat, bull nose, slot, face and thread mills all cut with a
        // cylindrical flat-bottomed profile as far as the heightmap is
        // concerned (bull nose's corner radius is ignored).
        if t.contains("flat") || t.contains("bull") || t.contains("slot")
            || t.contains("face") || t.contains("thread") || t.contains("end mill") {
            return .endMill
        }
        return nil
    }
}