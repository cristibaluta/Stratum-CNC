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
///     ;@MKR|MATERIAL|id=|name=other
///     ;@MKR|STOCK|id=cuboid|length=152|width=102|height=5.15|diameter=50
///     ;@MKR|TOOL|number=4|name=3.175*2*8mm Flat End(Metal)|type=Flat End|diameter=2|...
///     ;@MKR|END
///
/// Each line is `;@MKR|<RECORD>|key=value|key=value…`. `TOOL`, `STOCK` and
/// `MATERIAL` records are read; everything else is skipped. A `cuboid` stock
/// is the only shape `StockSpec` can describe: `length` runs along X, `width`
/// along Y and `height` along Z. Not a Makera file (no `BEGIN`) → `nil`.
struct MakeraHeaderParser: GCodeHeaderParser {

    private static let linePrefix = ";@MKR|"

    func parse(headerLines: [String]) -> GCodeHeader? {
        var sawBegin = false
        var tools: [Int: Tool] = [:]
        var stock: StockSpec?
        var materialName: String?

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
                return sawBegin ? Self.header(tools: tools, stock: stock, materialName: materialName) : nil
            case "MATERIAL":
                guard sawBegin else {
                    continue
                }
                let name = Self.keyValues(fields.dropFirst())["name"] ?? ""
                materialName = name.isEmpty ? nil : name
            case "STOCK":
                guard sawBegin,
                      let spec = Self.stock(from: Self.keyValues(fields.dropFirst())) else {
                    continue
                }
                stock = spec
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
        return sawBegin ? Self.header(tools: tools, stock: stock, materialName: materialName) : nil
    }

    // MARK: Helpers

    /// The stock carries the material name, but only when the header declared a stock: a
    /// material on its own says nothing about the size.
    private static func header(tools: [Int: Tool],
                               stock: StockSpec?,
                               materialName: String?) -> GCodeHeader {
        var spec = stock
        spec?.material = materialName
        return GCodeHeader(tools: tools, stock: spec)
    }

    /// Builds a `StockSpec` from one `STOCK` record. `nil` for a shape other than `cuboid`, or
    /// when a size is missing or not positive: the header then says nothing about the stock.
    private static func stock(from values: [String: String]) -> StockSpec? {
        guard values["id"]?.lowercased() == "cuboid",
              let length = values["length"].flatMap({ Double($0) }), length > 0,
              let width = values["width"].flatMap({ Double($0) }), width > 0,
              let height = values["height"].flatMap({ Double($0) }), height > 0 else {
            return nil
        }
        return StockSpec(sizeX: length, sizeY: width, sizeZ: height)
    }

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

    /// Builds a `Tool` from one `TOOL` record. `nil` if the number or
    /// diameter is missing, or the tool type isn't one `ToolType` can
    /// represent — that tool just stays "Unassigned" in the picker.
    private static func tool(from values: [String: String]) -> (Int, Tool)? {
        guard let number = values["number"].flatMap({ Int($0) }),
              let diameter = values["diameter"].flatMap({ Double($0) }), diameter > 0,
              let kind = kind(forType: values["type"] ?? "") else {
            return nil
        }

        // `diameter` is the cutting diameter; `handlediameter` is the shank.
        var tipAngle: Double?
        if kind == .vBit || kind == .engraving {
            let angle = values["angle"].flatMap { Double($0) } ?? 0
            let halfAngle = values["halfAngle"].flatMap { Double($0) } ?? 0
            tipAngle = angle > 0 ? angle : (halfAngle > 0 ? halfAngle * 2 : nil)
        }

        let name = values["name"].flatMap { $0.isEmpty ? nil : $0 } ?? "T\(number)"

        return (number, Tool(fromHeader: name,
                             diameter: diameter,
                             type: kind,
                             tipAngle: tipAngle))
    }

    private static func kind(forType type: String) -> ToolType? {
        let t = type.lowercased()
        if t.contains("ball") {
            return .ballNose
        }
        if t.contains("thread") {
            return .threadMill
        }
        if t.contains("flat") || t.contains("end mill") {
            return .endMill
        }
        if t.contains("v-bit") || t.contains("v bit") || t.contains("vbit") || t.contains("chamfer") {
            return .vBit
        }
        if t.contains("engrav") {
            return .engraving
        }
        if t.contains("drill") {
            return .drill
        }
        return nil
    }
}
