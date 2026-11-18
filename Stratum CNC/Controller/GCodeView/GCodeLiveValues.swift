//
//  GCodeLiveValues.swift
//  Stratum CNC
//
//  The feed rate and Z that are in effect at each line of a program. Both are modal in G-code
//  (they stay until a later line changes them), so the value at a line is the last one written
//  on or before it.
//

import Foundation

struct GCodeLiveValues: Equatable {

    /// Feed rate in effect, as written (`800`). Nil before the first `F`.
    var feed: String?
    /// Z in effect, as written (`-2.700`). Nil before the first Z word.
    var z: String?
    /// The last motion word was G0/G00, so the machine is rapiding and the feed doesn't apply.
    var isRapid = false

    /// One entry per line, in order (index 0 is line 1). Run when the program loads or a line is edited.
    static func parse(_ texts: [String]) -> [GCodeLiveValues] {
        var result: [GCodeLiveValues] = []
        result.reserveCapacity(texts.count)
        var current = GCodeLiveValues()

        for text in texts {
            var code = Substring(text)
            if let open = code.firstIndex(of: "(") {
                code = code[code.startIndex..<open]
            }
            if let semicolon = code.firstIndex(of: ";") {
                code = code[code.startIndex..<semicolon]
            }

            for token in code.split(whereSeparator: \.isWhitespace) {
                guard let letter = token.first?.uppercased() else {
                    continue
                }
                let value = String(token.dropFirst())
                switch letter {
                    case "Z":
                        if !value.isEmpty {
                            current.z = value
                        }
                    case "F":
                        if !value.isEmpty {
                            current.feed = value
                        }
                    case "G":
                        switch token.uppercased() {
                            case "G0", "G00":
                                current.isRapid = true
                            case "G1", "G01", "G2", "G02", "G3", "G03":
                                current.isRapid = false
                            default:
                                break
                        }
                    default:
                        break
                }
            }
            result.append(current)
        }
        return result
    }
}
