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
        lines.append(record("TIME", [("seconds", String(Int(seconds.rounded())))]))

        for (index, section) in sections.enumerated() {
            lines.append(record("TOOLPATH", [("number", String(index + 1)),
                                             ("tool_number", String(toolNumbers[section.tool.id] ?? 0)),
                                             ("name", section.name)]))
        }
        lines.append(";@MKR|END")
        lines.append("G90 G21")

        for (index, section) in sections.enumerated() {
            lines.append(";@MKR|TOOLPATH_START|toolpath_number=\(index + 1)")
            let toolNumber = toolNumbers[section.tool.id] ?? 0
            lines.append("; T\(toolNumber)-\(clean(section.tool.name))")
            lines.append(section.gcode)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Records

    private static func toolRecord(_ tool: Tool, number: Int) -> String {
        let flute = tool.length ?? 0
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
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text == "-0" ? "0" : text
    }

    // MARK: Time estimate

    /// Speed assumed for G0 moves, mm/min. The engine doesn't report a time, so this is the
    /// one made-up number in the estimate.
    private static let rapidRate = 3000.0

    private static let wordRegex = try! NSRegularExpression(pattern: #"([A-Za-z])\s*(-?[0-9]*\.?[0-9]+)"#)

    /// Rough machining time: path length over feed rate, straight from the G-code text.
    /// Ignores acceleration, dwells and tool changes, so real jobs run a little longer.
    static func estimateSeconds(of gcode: String) -> Double {
        var x = 0.0, y = 0.0, z = 0.0
        var feed = 0.0
        var mode = 0
        var minutes = 0.0

        for rawLine in gcode.split(whereSeparator: \.isNewline) {
            var line = String(rawLine)
            if let semicolon = line.firstIndex(of: ";") {
                line = String(line[..<semicolon])
            }
            line = line.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)

            var words: [(Character, Double)] = []
            for match in wordRegex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let letterRange = Range(match.range(at: 1), in: line),
                      let valueRange = Range(match.range(at: 2), in: line),
                      let letter = line[letterRange].uppercased().first,
                      let value = Double(line[valueRange]) else {
                    continue
                }
                words.append((letter, value))
            }

            var target = (x: x, y: y, z: z)
            var i = 0.0, j = 0.0
            var moves = false

            for (letter, value) in words {
                switch letter {
                case "G":
                    if [0, 1, 2, 3].contains(Int(value)) {
                        mode = Int(value)
                    }
                case "F": feed = value
                case "X": target.x = value; moves = true
                case "Y": target.y = value; moves = true
                case "Z": target.z = value; moves = true
                case "I": i = value
                case "J": j = value
                default: break
                }
            }
            guard moves else {
                continue
            }

            let dx = target.x - x, dy = target.y - y, dz = target.z - z
            var length = (dx * dx + dy * dy + dz * dz).squareRoot()

            if (mode == 2 || mode == 3), i != 0 || j != 0 {
                let radius = (i * i + j * j).squareRoot()
                let centerX = x + i, centerY = y + j
                let start = atan2(y - centerY, x - centerX)
                let end = atan2(target.y - centerY, target.x - centerX)
                var sweep = mode == 2 ? start - end : end - start
                while sweep <= 0 {
                    sweep += 2 * .pi
                }
                if dx == 0 && dy == 0 {
                    sweep = 2 * .pi
                }
                let arc = radius * sweep
                length = (arc * arc + dz * dz).squareRoot()
            }

            let rate = (mode == 0 || feed <= 0) ? rapidRate : feed
            minutes += length / rate

            (x, y, z) = target
        }
        return minutes * 60
    }
}
