//
//  MakeraCAMHeaderParser.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//

import Foundation

/// Parses the plain `;` comment block Makera CAM writes at the top of a
/// program — as opposed to the tagged `;@MKR|…` records `MakeraHeaderParser`
/// reads. It carries no vendor tag, so it's recognised purely by shape (the
/// Makera attribution is inferred from the tool naming and the 3-axis /
/// stock layout, not from a documented spec):
///
///     %
///     ; 3-Axis
///     ; Material: Aluminum
///     ; Stock Size: 100(X) * 100(Y) * 6(Z) mm
///     ; Tool List
///     ; T1-1*3mm Flat End(Metal)
///     ; T2-2*8mm Flat End(Metal)
///     ; T3-3.175*12mm Flat End(Metal)
///     ; Path List
///     ; [T3]3D Contour
///
/// Reads the stock size (plus its material name) and the tool list. The axis
/// count and the path list are skipped.
///
/// A tool line is `T<n>-<dimensions> <type>(<material>)`, where the
/// dimensions are `*`-separated numbers with an optional trailing unit:
///
///     1*3mm          diameter * length             → diameter 1
///     3.175*2*8mm    shank * diameter * length     → diameter 2
///
/// The three-number form is the one `MakeraHeaderParser` documents (its
/// `3.175*2*8mm Flat End(Metal)` has `diameter=2`). The length isn't kept —
/// `ToolSpec` has no field for it. Neither stock nor tools found → `nil`.
struct MakeraCAMHeaderParser: GCodeHeaderParser {

    /// A non-negative decimal: `6`, `3.175`, `6.`, `.5`.
    private static let number = #"(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)"#

    /// `; Stock Size: <everything>`.
    private static let stockLine = try! NSRegularExpression(
        pattern: #"^;\s*Stock\s*Size\s*:\s*(.+)$"#,
        options: [.caseInsensitive]
    )

    /// One `100(X)` term inside the stock size — the axis letter says which
    /// dimension it is, so the order they're written in doesn't matter.
    private static let stockTerm = try! NSRegularExpression(
        pattern: #"(\#(MakeraCAMHeaderParser.number))\s*\(\s*([XYZ])\s*\)"#,
        options: [.caseInsensitive]
    )

    /// Trailing unit on the stock size; absent means millimeters.
    private static let stockUnit = try! NSRegularExpression(
        pattern: #"\b(mm|in|inch)\s*$"#,
        options: [.caseInsensitive]
    )

    /// `; Material: Aluminum`.
    private static let materialLine = try! NSRegularExpression(
        pattern: #"^;\s*Material\s*:\s*(.+)$"#,
        options: [.caseInsensitive]
    )

    /// `; T<number>-<description>`. Requires digits right after the `T` and
    /// a hyphen, so `; [T3]3D Contour` path lines don't match.
    private static let toolLine = try! NSRegularExpression(
        pattern: #"^;\s*T(\d+)\s*-\s*(.+)$"#
    )

    /// `1*3mm Flat End(Metal)` → dimensions, unit, rest. The unit needs a
    /// word boundary so a type starting with "in..." isn't read as inches.
    private static let toolBody = try! NSRegularExpression(
        pattern: #"^((?:\#(MakeraCAMHeaderParser.number)\s*\*\s*)*\#(MakeraCAMHeaderParser.number))\s*(?:(mm|in|inch)\b)?\s*(.*)$"#,
        options: [.caseInsensitive]
    )

    func parse(headerLines: [String]) -> GCodeHeader? {
        var tools: [Int: ToolSpec] = [:]
        var size: (x: Double, y: Double, z: Double)?
        var material: String?

        for rawLine in headerLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(";") else {
                continue
            }

            if let parsedSize = Self.stockSize(in: line) {
                size = parsedSize
                continue
            }
            if let name = Self.captures(of: Self.materialLine, in: line)?.first {
                material = name.trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let parts = Self.captures(of: Self.toolLine, in: line),
                  parts.count == 2,
                  let number = Int(parts[0]),
                  tools[number] == nil,
                  let spec = Self.tool(description: parts[1]) else {
                continue
            }
            tools[number] = spec
        }

        var stock: StockSpec?
        if let size {
            stock = StockSpec(sizeX: size.x, sizeY: size.y, sizeZ: size.z,
                              material: (material?.isEmpty ?? true) ? nil : material)
        }

        guard !tools.isEmpty || stock != nil else {
            return nil
        }
        return GCodeHeader(tools: tools, stock: stock)
    }

    // MARK: Stock

    /// X/Y/Z stock size in millimeters if `line` is a `Stock Size:` comment
    /// carrying all three axes.
    private static func stockSize(in line: String) -> (x: Double, y: Double, z: Double)? {
        guard let body = captures(of: stockLine, in: line)?.first else {
            return nil
        }

        var sizes: [String: Double] = [:]
        for match in stockTerm.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let valueRange = Range(match.range(at: 1), in: body),
                  let axisRange = Range(match.range(at: 2), in: body),
                  let value = double(String(body[valueRange])) else {
                continue
            }
            sizes[body[axisRange].uppercased()] = value
        }

        guard let x = sizes["X"], let y = sizes["Y"], let z = sizes["Z"],
              x > 0, y > 0, z > 0 else {
            return nil
        }
        let scale = unitScale(captures(of: stockUnit, in: body)?.first)
        return (x * scale, y * scale, z * scale)
    }

    // MARK: Tools

    /// Builds a `ToolSpec` from what follows `T<n>-`. `nil` if the
    /// dimensions don't parse or the type isn't one `ToolSpec.Kind` can
    /// represent — that tool just stays "Unassigned" in the picker.
    private static func tool(description: String) -> ToolSpec? {
        guard let parts = captures(of: toolBody, in: description), parts.count == 3 else {
            return nil
        }

        let dimensions = parts[0]
            .split(separator: "*")
            .compactMap { double($0.trimmingCharacters(in: .whitespaces)) }

        // `diameter*length` or `shank*diameter*length`.
        let diameterIndex = dimensions.count == 3 ? 1 : 0
        guard dimensions.count <= 3,
              diameterIndex < dimensions.count,
              dimensions[diameterIndex] > 0 else {
            return nil
        }
        let diameter = dimensions[diameterIndex] * unitScale(parts[1])

        // Type is the text before the trailing `(Metal)` style qualifier.
        let type = parts[2]
            .prefix { $0 != "(" }
            .trimmingCharacters(in: .whitespaces)
        guard let kind = kind(forType: type) else {
            return nil
        }

        return ToolSpec(name: description,
                        diameterMM: diameter,
                        flutes: ToolSpec.assumedFlutes,
                        kind: kind)
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

    // MARK: Helpers

    /// Capture groups 1...n of the first match, `""` for a group that didn't
    /// take part. `nil` when the regex doesn't match at all.
    private static func captures(of regex: NSRegularExpression, in text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// `6.` → 6 — `Double("6.")` isn't reliable, so drop a bare trailing dot.
    private static func double(_ text: String) -> Double? {
        var number = text
        if number.hasSuffix(".") {
            number.removeLast()
        }
        return Double(number)
    }

    private static func unitScale(_ unit: String?) -> Double {
        switch unit?.lowercased() {
        case "in", "inch":
            return 25.4
        default:
            return 1
        }
    }
}
