//
//  SingleGerberParser.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//

import Foundation
import SwiftDXF

final class SingleGerberParser {

    // MARK: - Types

    private enum Interpolation {
        case linear
        case clockwise
        case counterClockwise
    }

    private enum QuadrantMode {
        case single
        case multi
    }

    private enum Aperture {
        case circle(diameter: Double)
        case rectangle(width: Double, height: Double)
    }

    private struct CoordinateCommand {
        var x: String?
        var y: String?
        var i: String?
        var j: String?
        var dCode: Int?
    }

    // MARK: - Properties

    private let source: String
    private let layer: String

    private var entities: [DXF.Entity] = []

    private var apertures: [Int: Aperture] = [:]
    private var currentAperture: Int?

    private var currentPoint = DXF.Point(0, 0)

    private var unitScale = 1.0

    private var formatIntegerDigits = 6
    private var formatDecimalDigits = 6

    private var interpolation: Interpolation = .linear
    private var quadrantMode: QuadrantMode = .single

    private var currentRegion: [DXF.Point] = []
    private var isInRegion = false

    // MARK: - Init

    init(source: String, layer: String) {
        self.source = source
        self.layer = layer
    }

    // MARK: - Public

    func parse() -> [DXF.Entity] {

        let commands = tokenize(source)

        for command in commands {
            parseCommand(command)
        }

        // Close any unfinished region.
        if isInRegion {
            finishRegion()
        }

        return entities
    }

    // MARK: - Tokenizer

    private func tokenize(_ source: String) -> [String] {

        var commands: [String] = []
        var current = ""

        var inExtendedCommand = false

        for character in source {

            current.append(character)

            if character == "%" {
                if inExtendedCommand {
                    commands.append(current)
                    current = ""
                    inExtendedCommand = false
                } else {
                    if !current.isEmpty {
                        commands.append(current)
                        current = ""
                    }

                    current = "%"
                    inExtendedCommand = true
                }

                continue
            }

            if !inExtendedCommand && character == "*" {
                commands.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            commands.append(current)
        }

        return commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Command Parsing

    private func parseCommand(_ command: String) {

        let command = command
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if command.isEmpty {
            return
        }

        // Units
        if command.contains("MOMM") {
            unitScale = 1.0
            return
        }

        if command.contains("MOIN") {
            unitScale = 25.4
            return
        }

        // Format specification
        if command.contains("FSLAX") {
            parseFormat(command)
            return
        }

        // Aperture definition
        if command.contains("%ADD") {
            parseAperture(command)
            return
        }

        // Region start/end
        if command.hasPrefix("G36") {
            isInRegion = true
            currentRegion.removeAll()
            return
        }

        if command.hasPrefix("G37") {
            finishRegion()
            return
        }

        // Interpolation
        if command.hasPrefix("G01") {
            interpolation = .linear
            return
        }

        if command.hasPrefix("G02") {
            interpolation = .clockwise
            return
        }

        if command.hasPrefix("G03") {
            interpolation = .counterClockwise
            return
        }

        // Quadrant mode
        if command.hasPrefix("G74") {
            quadrantMode = .single
            return
        }

        if command.hasPrefix("G75") {
            quadrantMode = .multi
            return
        }

        // Coordinate / D-code command
        parseCoordinateCommand(command)
    }

    // MARK: - Format

    private func parseFormat(_ command: String) {

        // Example:
        // %FSLAX46Y46*%

        guard let range = command.range(of: "FSLAX") else {
            return
        }

        let suffix = command[range.upperBound...]

        let digits = suffix.filter { $0.isNumber }

        guard digits.count >= 4 else {
            return
        }

        let values = Array(digits)

        formatIntegerDigits = Int(String(values[0])) ?? 6
        formatDecimalDigits = Int(String(values[1])) ?? 6
    }

    // MARK: - Apertures

    private func parseAperture(_ command: String) {

        // Examples:
        // %ADD10C,0.100000*%
        // %ADD17R,0.400000X3.200000*%

        let cleaned = command
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "*", with: "")

        guard cleaned.hasPrefix("ADD") else {
            return
        }

        let body = String(cleaned.dropFirst(3))

        guard let commaIndex = body.firstIndex(of: ",") else {
            return
        }

        let numberString = String(body[..<commaIndex])
        let definition = String(body[body.index(after: commaIndex)...])

        guard let apertureNumber = Int(numberString) else {
            return
        }

        let parts = definition.split(separator: ",")

        guard let type = parts.first else {
            return
        }

        let values = parts.dropFirst().joined(separator: ",")

        switch type {

        case "C":

            guard let diameter = Double(values) else {
                return
            }

            apertures[apertureNumber] = .circle(
                diameter: diameter
            )

        case "R":

            let dimensions = values
                .split(separator: "X")
                .compactMap { Double($0) }

            guard dimensions.count >= 2 else {
                return
            }

            apertures[apertureNumber] = .rectangle(
                width: dimensions[0],
                height: dimensions[1]
            )

        default:
            break
        }
    }

    // MARK: - D Codes

    private func parseDCode(_ command: String) {

        let cleaned = command
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.hasPrefix("D") else {
            return
        }

        let number = String(cleaned.dropFirst())

        guard let code = Int(number) else {
            return
        }

        // D01 / D02 / D03 are handled by coordinate commands.
        // D10+ selects an aperture.

        if code >= 10 {
            currentAperture = code
        }
    }

    // MARK: - Coordinates

    private func parseCoordinateCommand(_ command: String) {

        let cleaned = command
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.contains("D") else {
            return
        }

        let parsed = parseCoordinateFields(cleaned)

        guard let dCode = parsed.dCode else {
            return
        }

        let oldPoint = currentPoint

        let x = parsed.x.flatMap(parseCoordinate) ?? currentPoint.x
        let y = parsed.y.flatMap(parseCoordinate) ?? currentPoint.y

        let newPoint = DXF.Point(x, y)

        switch dCode {

        case 1:
            // D01 = draw
            draw(to: newPoint, from: oldPoint)

        case 2:
            // D02 = move
            currentPoint = newPoint

        case 3:
            // D03 = flash
            currentPoint = newPoint
            flash(at: newPoint)

        default:
            break
        }
    }

    private func parseCoordinateFields(
        _ command: String
    ) -> CoordinateCommand {

        var result = CoordinateCommand()

        var index = command.startIndex

        while index < command.endIndex {

            let character = command[index]

            guard character == "X" ||
                  character == "Y" ||
                  character == "I" ||
                  character == "J" ||
                  character == "D" else {
                index = command.index(after: index)
                continue
            }

            let nextIndex = command.index(after: index)

            var end = nextIndex

            while end < command.endIndex {

                let c = command[end]

                if c == "X" ||
                   c == "Y" ||
                   c == "I" ||
                   c == "J" ||
                   c == "D" {
                    break
                }

                end = command.index(after: end)
            }

            let value = String(command[nextIndex..<end])

            switch character {

            case "X":
                result.x = value

            case "Y":
                result.y = value

            case "I":
                result.i = value

            case "J":
                result.j = value

            case "D":
                result.dCode = Int(value)

            default:
                break
            }

            index = end
        }

        return result
    }

    // MARK: - Coordinate Conversion

    private func parseCoordinate(_ value: String) -> Double? {

        guard !value.isEmpty else {
            return nil
        }

        guard let integer = Int(value) else {
            return nil
        }

        let divisor = pow(
            10.0,
            Double(formatDecimalDigits)
        )

        return Double(integer) / divisor * unitScale
    }

    // MARK: - Drawing

    private func draw(
        to point: DXF.Point,
        from start: DXF.Point
    ) {

        guard start != point else {
            return
        }

        if isInRegion {
            currentRegion.append(start)
            currentRegion.append(point)
            currentPoint = point
            return
        }

        switch interpolation {

        case .linear:

            entities.append(
                .line(
                    a: start,
                    b: point,
                    layer: layer,
                    color: 256
                )
            )

        case .clockwise,
             .counterClockwise:

            // Gerber arcs require I/J offsets.
            // This simple POC only handles arcs when
            // the center can be calculated from the command.

            break
        }

        currentPoint = point
    }

    // MARK: - Flash

    private func flash(at point: DXF.Point) {

        guard let apertureNumber = currentAperture,
              let aperture = apertures[apertureNumber] else {
            return
        }

        switch aperture {

        case .circle(let diameter):

            entities.append(
                .circle(
                    center: point,
                    radius: diameter / 2 * unitScale,
                    layer: layer,
                    color: 256
                )
            )

        case .rectangle(let width, let height):

            let hw = width / 2 * unitScale
            let hh = height / 2 * unitScale

            let vertices = [
                DXF.PolyVertex(
                    DXF.Point(point.x - hw, point.y - hh)
                ),
                DXF.PolyVertex(
                    DXF.Point(point.x + hw, point.y - hh)
                ),
                DXF.PolyVertex(
                    DXF.Point(point.x + hw, point.y + hh)
                ),
                DXF.PolyVertex(
                    DXF.Point(point.x - hw, point.y + hh)
                )
            ]

            entities.append(
                .polyline(
                    vertices: vertices,
                    closed: true,
                    layer: layer,
                    color: 256
                )
            )
        }
    }

    // MARK: - Regions

    private func finishRegion() {

        guard currentRegion.count >= 3 else {
            currentRegion.removeAll()
            isInRegion = false
            return
        }

        let vertices = currentRegion.map {
            DXF.PolyVertex($0)
        }

        entities.append(
            .polyline(
                vertices: vertices,
                closed: true,
                layer: layer,
                color: 256
            )
        )

        currentRegion.removeAll()
        isInRegion = false
    }
}
