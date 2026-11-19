//
//  MakeraGCodeHeaderWriter.swift
//  Stratum CNC
//
//  Writes the `;@MKR|…` block Makera Studio puts at the top of its programs, plus the
//  per-toolpath markers that go between the sections of the program body. It's the
//  counterpart of `MakeraHeaderParser`, which reads the same format back.
//
//      ;@MKR|BEGIN
//      ;@MKR|SCHEMA|v=1.0.0
//      ;@MKR|MACHINE|id=CA1|name=Carvera Air
//      ;@MKR|MATERIAL|id=|name=Aluminum
//      ;@MKR|STOCK|id=cuboid|length=100|width=100|height=6|diameter=0
//      ;@MKR|CAM|id=stratum-cnc|name=Stratum CNC|v=1.0
//      ;@MKR|TOOL|number=1|id=|name=3.175*2*8mm Flat End(Metal)|type=Flat End|…
//      ;@MKR|TIME|seconds=3120
//      ;@MKR|TOOLPATH|number=1|tool_number=1|name=Contour
//      ;@MKR|END
//      G90 G21
//      ;@MKR|TOOLPATH_START|toolpath_number=1
//      ; T1-3.175*2*8mm Flat End(Metal)
//      T1 M6
//      …engine G-code for toolpath 1…
//
//  Pure string building — no shared state, safe on any thread.
//

import Foundation

enum MakeraGCodeHeaderWriter {

    // MARK: Inputs

    struct Machine: Sendable {
        var id: String
        var name: String

        static let carveraAir = Machine(id: "CA1", name: "Carvera Air")
    }

    /// What the header says about the job besides the toolpaths themselves.
    struct JobInfo: Sendable {
        var machine: Machine = .carveraAir
        /// `nil` → no MATERIAL / STOCK lines.
        var stock: StockMaterial?
        /// The setup this program cuts, when the project has several: named in a comment so the
        /// operator knows how to put the stock down. `nil` → no such line.
        var setup: Setup?
        var camName = "Stratum CNC"
        var camVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// One toolpath's slice of the program, already through the G-code engine.
    struct Section: Sendable {
        let name: String
        let tool: Tool
        let gcode: String
    }

    // MARK: Program

    /// Header + every section, with the markers between them.
    static func program(sections: [Section], job: JobInfo) -> String {

        // Tool numbers follow first use, so T1 is whatever the program cuts with first.
        var toolNumbers: [UUID: Int] = [:]
        var toolsInOrder: [Tool] = []
        for section in sections where toolNumbers[section.tool.id] == nil {
            toolsInOrder.append(section.tool)
            toolNumbers[section.tool.id] = toolsInOrder.count
        }

        var lines: [String] = []
        lines.append(";@MKR|BEGIN")
        lines.append(";@MKR|SCHEMA|v=1.0.0")
        lines.append(record("MACHINE", [("id", job.machine.id), ("name", job.machine.name)]))

        if let stock = job.stock {
            lines.append(record("MATERIAL", [("id", ""), ("name", materialName(stock.material))]))
            if let stockRecord = stockRecord(stock.geometry) {
                lines.append(stockRecord)
            }
        }

        lines.append(record("CAM", [("id", "stratum-cnc"), ("name", job.camName), ("v", job.camVersion)]))

        for tool in toolsInOrder {
            lines.append(toolRecord(tool, number: toolNumbers[tool.id] ?? 0))
        }

        let seconds = sections.reduce(0.0) { $0 + estimateSeconds(of: $1.gcode) }
        lines.append(record("TIME", [("seconds", String(seconds.roundedInt))]))

        for (index, section) in sections.enumerated() {
            lines.append(record("TOOLPATH", [("number", String(index + 1)),
                                             ("tool_number", String(toolNumbers[section.tool.id] ?? 0)),
                                             ("name", section.name)]))
        }
        lines.append(";@MKR|END")
        lines.append("G90 G21")
        if let setup = job.setup {
            lines.append("; Setup: \(clean(setup.name)) (\(setup.orientationTitle), stock turned \(setup.angle.roundedInt) deg about \(setup.axis.title))")
        }

        for (index, section) in sections.enumerated() {
            lines.append(";@MKR|TOOLPATH_START|toolpath_number=\(index + 1)")
            let toolNumber = toolNumbers[section.tool.id] ?? 0
            lines.append("; T\(toolNumber)-\(clean(section.tool.name))")
            // StratumCAM doesn't know the tool's number, so it can't write the change itself.
            lines.append("T\(toolNumber) M6")
            lines.append(section.gcode)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Records

    private static func toolRecord(_ tool: Tool, number: Int) -> String {
        let flute = tool.cuttingHeight ?? 0
        let angle = tool.tipAngle ?? 0
        let cornerRadius = tool.type == .ballNose ? tool.toolDiameter / 2 : 0

        return record("TOOL", [
            ("number", String(number)),
            // Makera's own catalogue id. Stratum's tools don't have one.
            ("id", ""),
            ("name", tool.name),
            ("type", typeName(tool.type)),
            ("handlediameter", format(tool.shankDiameter)),
            ("sticklength", "0"),
            ("shoulderlength", format(flute)),
            ("flutelength", format(flute)),
            ("diameter", format(tool.toolDiameter)),
            ("tipdiameter", format(tool.toolDiameter)),
            ("cornerradius", format(cornerRadius)),
            ("angle", format(angle)),
            ("halfAngle", format(angle / 2))
        ])
    }

    /// Length is along X, width along Y, height along Z. Disks have no Makera equivalent
    /// that this reader knows, so they get no STOCK line.
    private static func stockRecord(_ geometry: StockGeometry) -> String? {
        switch geometry {
        case let .rectangular(width, height, depth):
            return record("STOCK", [("id", "cuboid"), ("length", format(width)), ("width", format(height)),
                                    ("height", format(depth)), ("diameter", "0")])
        case let .cylindrical(diameter, length):
            return record("STOCK", [("id", "cylinder"), ("length", "0"), ("width", "0"),
                                    ("height", format(length)), ("diameter", format(diameter))])
        case .disk:
            return nil
        }
    }

    private static func typeName(_ type: ToolType) -> String {
        switch type {
        case .endMill:            return "Flat End"
        case .ballNose:           return "Ball End"
        case .engraving:          return "Engraving"
        case .drill:              return "Drill"
        case .vBit:               return "V-Bit"
        case .corn:               return "Corn"
        case .chamfer:            return "Chamfer"
        case .solderMaskRemover:  return "Solder Mask Remover"
        case .threadMill:         return "Thread Mill"
        }
    }

    private static func materialName(_ type: StockMaterialType) -> String {
        type == .custom ? "other" : type.displayName
    }

    // MARK: Formatting

    private static func record(_ name: String, _ fields: [(String, String)]) -> String {
        ";@MKR|\(name)|" + fields.map { "\($0.0)=\(clean($0.1))" }.joined(separator: "|")
    }

    /// `|` separates fields and a newline ends the record, so neither can appear in a value.
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// `3.175`, `12`, `0.1` — no trailing zeros, no exponent.
    private static func format(_ value: Double) -> String {
        var text = value.fixed(4)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text == "-0" ? "0" : text
    }

    // MARK: Time estimate

    /// Rough machining time, see `GCodeTimeEstimator`.
    static func estimateSeconds(of gcode: String) -> Double {
        GCodeTimeEstimator.estimateSeconds(of: gcode)
    }
}
