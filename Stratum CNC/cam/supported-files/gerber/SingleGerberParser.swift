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

    // How finely arcs are tessellated when they fall inside a G36/G37
    // region (regions are stored as plain point lists, so curved edges
    // need to be approximated with short line segments).
    private let arcTessellationDegreesPerSegment = 6.0

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

        // D-codes of 10 and above select an aperture; they carry no
        // coordinate/draw semantics of their own. Previously this fell
        // through to the switch below and hit `default: break`, so the
        // aperture was never actually selected and every subsequent
        // flash (D03) silently did nothing.
        if dCode >= 10 {
            currentAperture = dCode
            return
        }

        let oldPoint = currentPoint

        let x = parsed.x.flatMap(parseCoordinate) ?? currentPoint.x
        let y = parsed.y.flatMap(parseCoordinate) ?? currentPoint.y
        let i = parsed.i.flatMap(parseCoordinate)
        let j = parsed.j.flatMap(parseCoordinate)

        let newPoint = DXF.Point(x, y)

        switch dCode {

        case 1:
            // D01 = draw
            draw(to: newPoint, from: oldPoint, i: i, j: j)

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
        from start: DXF.Point,
        i: Double?,
        j: Double?
    ) {

        guard start != point else {
            return
        }

        if isInRegion {

            if interpolation != .linear,
               let arcPoints = tessellateArc(from: start, to: point, i: i, j: j, clockwise: interpolation == .clockwise) {
                currentRegion.append(contentsOf: arcPoints)
            } else {
                currentRegion.append(start)
                currentRegion.append(point)
            }

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

            if let arc = makeArcEntity(from: start, to: point, i: i, j: j, clockwise: interpolation == .clockwise) {
                entities.append(arc)
            } else {
                // Couldn't resolve the arc center from the I/J offsets
                // (e.g. missing data) - fall back to a straight segment
                // so the contour at least stays connected.
                entities.append(
                    .line(
                        a: start,
                        b: point,
                        layer: layer,
                        color: 256
                    )
                )
            }
        }

        currentPoint = point
    }

    // MARK: - Arc geometry

    /// Resolves the arc's center/radius/endpoint-angles from the Gerber
    /// I/J offsets. In multi-quadrant mode (G75) the offsets are signed
    /// and unambiguous. In single-quadrant mode (G74) the offsets are
    /// unsigned, so all four sign combinations are tried and the one
    /// that (a) produces a consistent radius at both endpoints and
    /// (b) sweeps 90 degrees or less is kept.
    private func arcGeometry(
        from start: DXF.Point,
        to end: DXF.Point,
        iOffset: Double,
        jOffset: Double,
        clockwise: Bool
    ) -> (center: DXF.Point, radius: Double, startAngle: Double, endAngle: Double)? {

        let candidateOffsets: [(Double, Double)]

        if quadrantMode == .multi {
            candidateOffsets = [(iOffset, jOffset)]
        } else {
            let ai = abs(iOffset)
            let aj = abs(jOffset)
            candidateOffsets = [(ai, aj), (ai, -aj), (-ai, aj), (-ai, -aj)]
        }

        var best: (center: DXF.Point, radius: Double, startAngle: Double, endAngle: Double, error: Double)?

        for (di, dj) in candidateOffsets {

            let center = DXF.Point(start.x + di, start.y + dj)

            let r1 = hypot(start.x - center.x, start.y - center.y)
            let r2 = hypot(end.x - center.x, end.y - center.y)

            guard r1 > 0.0000001 else {
                continue
            }

            let radiusError = abs(r1 - r2)

            let startAngle = normalizedDegrees(atan2(start.y - center.y, start.x - center.x))
            let endAngle = normalizedDegrees(atan2(end.y - center.y, end.x - center.x))

            if quadrantMode == .single {
                let sweep = sweepDegrees(from: startAngle, to: endAngle, clockwise: clockwise)
                // Single-quadrant arcs are always <= 90 degrees; reject
                // sign combinations that don't satisfy that.
                guard sweep <= 90.5 else {
                    continue
                }
            }

            if best == nil || radiusError < best!.error {
                best = (center, (r1 + r2) / 2, startAngle, endAngle, radiusError)
            }
        }

        guard let result = best else {
            return nil
        }

        return (result.center, result.radius, result.startAngle, result.endAngle)
    }

    private func normalizedDegrees(_ radians: Double) -> Double {
        var degrees = radians * 180.0 / .pi
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 {
            degrees += 360
        }
        return degrees
    }

    private func sweepDegrees(from startAngle: Double, to endAngle: Double, clockwise: Bool) -> Double {
        var sweep = clockwise ? (startAngle - endAngle) : (endAngle - startAngle)
        sweep = sweep.truncatingRemainder(dividingBy: 360)
        if sweep <= 0 {
            sweep += 360
        }
        return sweep
    }

    /// Builds a DXF arc entity for a contour segment.
    ///
    /// NOTE: this assumes `DXF.Entity` exposes a
    /// `.arc(center:radius:startAngle:endAngle:layer:color:)` case with
    /// angles in degrees, following the standard DXF convention where an
    /// ARC always sweeps counter-clockwise from startAngle to endAngle.
    /// If your version of SwiftDXF names this case/parameters
    /// differently, adjust this one call accordingly.
    private func makeArcEntity(
        from start: DXF.Point,
        to end: DXF.Point,
        i: Double?,
        j: Double?,
        clockwise: Bool
    ) -> DXF.Entity? {

        guard let i = i, let j = j,
              let geo = arcGeometry(from: start, to: end, iOffset: i, jOffset: j, clockwise: clockwise) else {
            return nil
        }

        // DXF ARC entities always sweep counter-clockwise from startAngle
        // to endAngle. A clockwise Gerber arc traces the exact same set
        // of points as a counter-clockwise arc between the same two
        // angles in reverse order, so we swap them here.
        let startAngle = clockwise ? geo.endAngle : geo.startAngle
        let endAngle = clockwise ? geo.startAngle : geo.endAngle

        return .arc(
            center: geo.center,
            radius: geo.radius,
            startDeg: startAngle,
            endDeg: endAngle,
            layer: layer,
            color: 256
        )
    }

    /// Approximates an arc segment as a series of points, for use inside
    /// G36/G37 regions (which are stored/emitted as a plain polyline).
    private func tessellateArc(
        from start: DXF.Point,
        to end: DXF.Point,
        i: Double?,
        j: Double?,
        clockwise: Bool
    ) -> [DXF.Point]? {

        guard let i = i, let j = j,
              let geo = arcGeometry(from: start, to: end, iOffset: i, jOffset: j, clockwise: clockwise) else {
            return nil
        }

        let sweep = sweepDegrees(from: geo.startAngle, to: geo.endAngle, clockwise: clockwise)
        let segmentCount = max(Int((sweep / arcTessellationDegreesPerSegment).rounded(.up)), 2)

        var points: [DXF.Point] = []
        points.reserveCapacity(segmentCount + 1)

        for step in 0...segmentCount {
            let t = Double(step) / Double(segmentCount)
            let angle = clockwise ? geo.startAngle - sweep * t : geo.startAngle + sweep * t
            let radians = angle * .pi / 180
            points.append(
                DXF.Point(
                    geo.center.x + geo.radius * cos(radians),
                    geo.center.y + geo.radius * sin(radians)
                )
            )
        }

        return points
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
