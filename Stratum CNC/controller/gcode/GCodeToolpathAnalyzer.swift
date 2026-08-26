//
//  GCodeToolpathAnalyzer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation

struct GCodeToolpathAnalyzer {
    private static let codeRegex = try! NSRegularExpression(pattern: #"(?i)(?:^|\s)([GMT])\s*([0-9]+(?:\.[0-9]+)?)"#)
    private static let toolRegex = try! NSRegularExpression(pattern: #"(?i)(?:^|\s)T\s*([0-9]+)"#)

    static func analyze(_ lines: [(id: Int, text: String)]) -> [GCodeToolpath] {
        var result: [GCodeToolpath] = []
        var currentTool: Int?
        var currentOperation = "Motion"
        var currentStart: Int?
        var currentEnd: Int?
        var motionCount = 0
        var currentKind: OperationKind?

        func finishCurrent() {
            guard let start = currentStart, let end = currentEnd, motionCount > 0 else {
                currentStart = nil
                currentEnd = nil
                motionCount = 0
                currentKind = nil
                return
            }

            result.append(
                GCodeToolpath(
                    toolNumber: currentTool,
                    operation: currentOperation,
                    startLine: start,
                    endLine: end,
                    motionCount: motionCount
                )
            )

            currentStart = nil
            currentEnd = nil
            motionCount = 0
            currentKind = nil
        }

        for line in lines {
            let text = stripComments(line.text)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let codes = extractCodes(from: text)

            // Tool changes define a hard boundary between machining tools.
            if let tool = extractToolNumber(from: text), containsM6(codes) {
                finishCurrent()
                currentTool = tool
                currentOperation = "Tool \(tool)"
                continue
            }

            // Explicit drilling cycles are treated as their own operation.
            if let cycle = drillingCycle(in: codes) {
                if currentKind != .drilling {
                    finishCurrent()
                    currentOperation = "Drilling (G\(cycle))"
                    currentKind = .drilling
                }
                if currentStart == nil { currentStart = line.id }
                currentEnd = line.id
                motionCount += 1
                continue
            }

            // Cancelled canned cycle: close the drilling group.
            if containsCode(0, in: codes, letter: "G"), currentKind == .drilling {
                finishCurrent()
            }

            if let motion = motionCode(in: codes) {
                let kind: OperationKind = motion == 0 ? .rapid : .cutting

                // Split when the semantic motion type changes, while keeping
                // consecutive cutting moves together as one toolpath.
                if currentKind != kind {
                    finishCurrent()
                    currentKind = kind
                    currentOperation = kind == .rapid ? "Rapid" : "Cutting"
                }

                // Rapid moves are useful for context but are not called a
                // machining toolpath unless they contain an actual move.
                if currentStart == nil { currentStart = line.id }
                currentEnd = line.id
                motionCount += 1
            }
        }

        finishCurrent()

        // Rapid-only sections are generally setup/repositioning rather than
        // toolpaths. Keep them only when there is no cutting/drilling result.
        let machining = result.filter { $0.operation != "Rapid" }
        return machining.isEmpty ? result : machining
    }

    private enum OperationKind: Equatable {
        case rapid
        case cutting
        case drilling
    }

    private static func stripComments(_ text: String) -> String {
        var output = text

        if let semicolon = output.firstIndex(of: ";") {
            output = String(output[..<semicolon])
        }

        while let start = output.firstIndex(of: "(") {
            guard let end = output[start...].firstIndex(of: ")") else {
                output = String(output[..<start])
                break
            }
            output.removeSubrange(start...end)
        }

        return output
    }

    private static func extractCodes(from text: String) -> [(letter: String, value: Int)] {
        let range = NSRange(text.startIndex..., in: text)
        return codeRegex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let letterRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]) else { return nil }
            return (String(text[letterRange]).uppercased(), Int(value))
        }
    }

    private static func extractToolNumber(from text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = toolRegex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[valueRange])
    }

    private static func containsM6(_ codes: [(letter: String, value: Int)]) -> Bool {
        codes.contains { $0.letter == "M" && $0.value == 6 }
    }

    private static func motionCode(in codes: [(letter: String, value: Int)]) -> Int? {
        codes.last(where: { $0.letter == "G" && [0, 1, 2, 3].contains($0.value) })?.value
    }

    private static func drillingCycle(in codes: [(letter: String, value: Int)]) -> Int? {
        codes.last(where: { $0.letter == "G" && (81...89).contains($0.value) })?.value
    }

    private static func containsCode(_ value: Int, in codes: [(letter: String, value: Int)], letter: String) -> Bool {
        codes.contains { $0.letter == letter && $0.value == value }
    }
}
