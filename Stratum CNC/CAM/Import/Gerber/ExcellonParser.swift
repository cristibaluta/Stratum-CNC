//
//  ExcellonParser.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 09.09.2026.
//
//  Excellon drill files use a different command language than Gerber
//  (RS-274X). Feeding a .drl file through SingleGerberParser silently
//  produced no holes, since it doesn't understand T-code tool
//  definitions/selections or bare "X..Y.." coordinate lines. This is a
//  small, dedicated parser for that format.
//
//  Handles the common subset produced by KiCad and most other EDA
//  tools: M48 header, METRIC/INCH with optional LZ/TZ zero suppression
//  and an explicit digit-format hint (e.g. "METRIC,TZ,000.000"),
//  T-code tool definitions (T01C0.300) and selections (T01), and
//  X/Y drill-hit coordinates, either as zero-suppressed integers or as
//  literal decimals. Routing (slots via G85/G00 "rout" mode) is out of
//  scope for this POC - only single-hit drill holes are emitted.

import Foundation
import SwiftDXF

final class ExcellonParser {

    private enum ZeroSuppression {
        case leading
        case trailing
    }

    // MARK: - Properties

    private let source: String
    private let layer: String

    private var entities: [DXF.Entity] = []

    private var tools: [Int: Double] = [:]
    private var currentTool: Int?

    private var currentPoint = DXF.Point(0, 0)

    private var unitScale = 1.0

    private var integerDigits = 3
    private var decimalDigits = 3
    private var zeroSuppression: ZeroSuppression = .trailing

    // MARK: - Init

    init(source: String, layer: String) {
        self.source = source
        self.layer = layer
    }

    // MARK: - Public

    func parse() -> [DXF.Entity] {

        let lines = source.components(separatedBy: .newlines)

        for rawLine in lines {
            parseLine(rawLine)
        }

        return entities
    }

    // MARK: - Line parsing

    private func parseLine(_ rawLine: String) {

        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !line.isEmpty, !line.hasPrefix(";") else {
            return
        }

        if line == "%" {
            return
        }

        if line.hasPrefix("M48") ||
           line.hasPrefix("M95") ||
           line.hasPrefix("M30") ||
           line.hasPrefix("M00") {
            return
        }

        if line.hasPrefix("M71") {
            unitScale = 1.0
            return
        }

        if line.hasPrefix("M72") {
            unitScale = 25.4
            return
        }

        if line.hasPrefix("FMAT") {
            return
        }

        if line.hasPrefix("METRIC") {
            parseUnits(line, scale: 1.0)
            return
        }

        if line.hasPrefix("INCH") {
            parseUnits(line, scale: 25.4)
            return
        }

        if line.hasPrefix("G90") || line.hasPrefix("G91") {
            return
        }

        // Strip a leading G-code (e.g. "G05X001000Y002000") so a drill
        // hit combined with a mode command on one line isn't dropped.
        line = stripLeadingGCode(line)

        guard !line.isEmpty else {
            return
        }

        if line.hasPrefix("T") {
            parseToolLine(line)
            return
        }

        if line.hasPrefix("X") || line.hasPrefix("Y") {
            parseCoordinateLine(line)
            return
        }
    }

    private func stripLeadingGCode(_ line: String) -> String {

        guard line.hasPrefix("G") else {
            return line
        }

        var index = line.index(after: line.startIndex)

        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }

        return String(line[index...])
    }

    // MARK: - Units / format

    private func parseUnits(_ line: String, scale: Double) {

        unitScale = scale

        let parts = line.split(separator: ",").map { String($0) }

        for part in parts.dropFirst() {

            if part == "LZ" {
                zeroSuppression = .leading
            } else if part == "TZ" {
                zeroSuppression = .trailing
            } else if part.contains(".") {
                let components = part.split(separator: ".")
                if components.count == 2 {
                    integerDigits = components[0].count
                    decimalDigits = components[1].count
                }
            }
        }
    }

    // MARK: - Tools

    private func parseToolLine(_ line: String) {

        // Examples:
        // T1C0.0135        (definition, inch)
        // T01C0.300F00S00  (definition, metric, with feed/speed)
        // T01              (selection)

        let body = String(line.dropFirst())

        var digitsEndIndex = body.startIndex
        while digitsEndIndex < body.endIndex, body[digitsEndIndex].isNumber {
            digitsEndIndex = body.index(after: digitsEndIndex)
        }

        let numberString = String(body[body.startIndex..<digitsEndIndex])

        guard let toolNumber = Int(numberString) else {
            return
        }

        let remainder = String(body[digitsEndIndex...])

        if remainder.isEmpty {
            currentTool = toolNumber
            return
        }

        guard let cRange = remainder.range(of: "C") else {
            currentTool = toolNumber
            return
        }

        var diameterDigits = ""
        for character in remainder[cRange.upperBound...] {
            if character.isNumber || character == "." {
                diameterDigits.append(character)
            } else {
                break
            }
        }

        if let diameter = Double(diameterDigits) {
            tools[toolNumber] = diameter * unitScale
        }

        currentTool = toolNumber
    }

    // MARK: - Coordinates

    private func parseCoordinateLine(_ line: String) {

        var xString: String?
        var yString: String?

        var index = line.startIndex

        while index < line.endIndex {

            let character = line[index]

            guard character == "X" || character == "Y" else {
                index = line.index(after: index)
                continue
            }

            let nextIndex = line.index(after: index)
            var end = nextIndex

            while end < line.endIndex, line[end] != "X", line[end] != "Y" {
                end = line.index(after: end)
            }

            let value = String(line[nextIndex..<end])

            if character == "X" {
                xString = value
            } else {
                yString = value
            }

            index = end
        }

        let x = xString.map(parseCoordinateValue) ?? currentPoint.x
        let y = yString.map(parseCoordinateValue) ?? currentPoint.y

        currentPoint = DXF.Point(x, y)

        guard let toolNumber = currentTool, let diameter = tools[toolNumber] else {
            return
        }

        entities.append(
            .circle(
                center: currentPoint,
                radius: diameter / 2,
                layer: layer,
                color: 256
            )
        )
    }

    private func parseCoordinateValue(_ raw: String) -> Double {

        if raw.contains(".") {
            return (Double(raw) ?? 0) * unitScale
        }

        var digits = raw
        var negative = false

        if digits.hasPrefix("-") {
            negative = true
            digits.removeFirst()
        } else if digits.hasPrefix("+") {
            digits.removeFirst()
        }

        let totalDigits = integerDigits + decimalDigits

        switch zeroSuppression {

        case .trailing:
            // Trailing zeros were omitted from the file - pad them back
            // on the right.
            if digits.count < totalDigits {
                digits += String(repeating: "0", count: totalDigits - digits.count)
            }

        case .leading:
            // Leading zeros were omitted - pad them back on the left.
            if digits.count < totalDigits {
                digits = String(repeating: "0", count: totalDigits - digits.count) + digits
            }
        }

        guard let integerValue = Int(digits) else {
            return 0
        }

        let divisor = pow(10.0, Double(decimalDigits))
        let value = Double(integerValue) / divisor

        return (negative ? -value : value) * unitScale
    }
}
