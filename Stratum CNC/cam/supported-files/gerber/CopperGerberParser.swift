//
//  CopperGerberParser.swift
//  Stratum CNC
//
//  Converts Gerber copper into physical filled geometry before DXF/toolpath generation.
//

import Foundation
import CoreGraphics
import SwiftDXF
import iOverlay

/// Parses a positive/negative Gerber copper layer into merged filled contours.
///
/// This is deliberately separate from `SingleGerberParser`: display layers can keep
/// their original DXF primitives, while copper layers need physical-width geometry
/// and polygon boolean operations for CNC toolpaths.
final class CopperGerberParser {

    private enum Polarity {
        case dark
        case clear
    }

    private enum Aperture {
        case circle(diameter: Double)
        case rectangle(width: Double, height: Double)
        case roundRect(radius: Double, corners: [CGPoint])
    }

    private struct CoordinateCommand {
        var x: String?
        var y: String?
        var i: String?
        var j: String?
        var dCode: Int?
    }

    private let source: String
    private let layer: String

    private var apertures: [Int: Aperture] = [:]
    private var currentAperture: Int?
    private var currentPoint = CGPoint.zero
    private var unitScale = 1.0
    private var formatDecimalDigits = 6
    private var polarity: Polarity = .dark

    private var positivePaths: [[CGPoint]] = []
    private var negativePaths: [[CGPoint]] = []

    private var inRegion = false
    private var regionPoints: [CGPoint] = []

    init(source: String, layer: String) {
        self.source = source
        self.layer = layer
    }

    func parse() -> [DXF.Entity] {
        for command in tokenize(source) {
            parseCommand(command)
        }

        if inRegion {
            finishRegion()
        }

        return mergedEntities()
    }

    // MARK: - Tokenizer

    private func tokenize(_ source: String) -> [String] {
        var commands: [String] = []
        var current = ""
        var inExtended = false

        for character in source {
            current.append(character)

            if character == "%" {
                if inExtended {
                    commands.append(current)
                    current.removeAll(keepingCapacity: true)
                    inExtended = false
                } else {
                    if !current.dropLast().isEmpty {
                        commands.append(String(current.dropLast()))
                    }
                    current = "%"
                    inExtended = true
                }
                continue
            }

            if !inExtended && character == "*" {
                commands.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commands.append(current)
        }

        return commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Commands

    private func parseCommand(_ command: String) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        if command.contains("MOMM") {
            unitScale = 1.0
            return
        }

        if command.contains("MOIN") {
            unitScale = 25.4
            return
        }

        if command.contains("FSLAX") {
            parseFormat(command)
            return
        }

        if command.contains("%ADD") {
            parseAperture(command)
            return
        }

        if command.contains("%LPD") || command.hasPrefix("LPD") {
            polarity = .dark
            return
        }

        if command.contains("%LPC") || command.hasPrefix("LPC") {
            polarity = .clear
            return
        }

        if command.hasPrefix("G36") {
            inRegion = true
            regionPoints.removeAll(keepingCapacity: true)
            return
        }

        // D10+ selects an aperture.  This is separate from D01/D02/D03,
        // which are drawing operations attached to coordinate commands.
        // Without this state change, every D01/D03 on a copper layer has no
        // aperture and is therefore silently discarded.
        if let apertureNumber = standaloneApertureSelection(command) {
            currentAperture = apertureNumber
            return
        }

        if command.hasPrefix("G37") {
            finishRegion()
            return
        }

        parseCoordinateCommand(command)
    }

    private func standaloneApertureSelection(_ command: String) -> Int? {
        let cleaned = command
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.first == "D",
              cleaned.count >= 3,
              let code = Int(cleaned.dropFirst()),
              code >= 10 else {
            return nil
        }

        return code
    }

    private func parseFormat(_ command: String) {
        guard let range = command.range(of: "FSLAX") else { return }
        let suffix = command[range.upperBound...]
        let digits = suffix.filter(\.isNumber)
        guard digits.count >= 4 else { return }

        let values = Array(digits)
        formatDecimalDigits = Int(String(values[1])) ?? 6
    }

    // MARK: - Apertures

    private func parseAperture(_ command: String) {
        let cleaned = command
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "*", with: "")

        guard let addRange = cleaned.range(of: "ADD") else { return }
        let body = String(cleaned[addRange.upperBound...])

        guard let comma = body.firstIndex(of: ",") else { return }
        let header = String(body[..<comma])
        let definition = String(body[body.index(after: comma)...])

        // Find the aperture number at the start of the ADD definition.
        let digits = header.prefix(while: \.isNumber)
        guard let number = Int(digits) else { return }
        let type = String(header.dropFirst(digits.count))

        switch type {
        case "C":
            guard let diameter = Double(definition) else { return }
            apertures[number] = .circle(diameter: diameter)

        case "R":
            let values = definition
                .split(separator: "X")
                .compactMap { Double($0) }
            guard values.count >= 2 else { return }
            apertures[number] = .rectangle(width: values[0], height: values[1])

        case "RoundRect":
            let values = definition
                .split(separator: "X")
                .compactMap { Double($0) }
            guard values.count >= 9 else { return }

            let radius = values[0]
            let corners = stride(from: 1, through: 8, by: 2).map {
                CGPoint(x: values[$0], y: values[$0 + 1])
            }
            apertures[number] = .roundRect(radius: radius, corners: corners)

        default:
            // Other aperture macros are intentionally left for the general parser.
            break
        }
    }

    // MARK: - Coordinates

    private func parseCoordinateCommand(_ command: String) {
        let cleaned = command
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parsed = parseCoordinateFields(cleaned)
        guard let dCode = parsed.dCode else { return }

        let oldPoint = currentPoint
        let x = parsed.x.flatMap(parseCoordinate) ?? currentPoint.x
        let y = parsed.y.flatMap(parseCoordinate) ?? currentPoint.y
        let newPoint = CGPoint(x: x, y: y)

        switch dCode {
        case 1:
            if inRegion {
                if regionPoints.isEmpty { regionPoints.append(oldPoint) }
                regionPoints.append(newPoint)
            } else {
                stroke(from: oldPoint, to: newPoint)
            }
            currentPoint = newPoint

        case 2:
            if inRegion && !regionPoints.isEmpty && regionPoints.last != newPoint {
                // A region normally consists of connected D01 moves. A D02 starts a
                // new contour, so preserve the previous contour before moving.
                finishRegion()
                inRegion = true
                regionPoints = [newPoint]
            }
            currentPoint = newPoint

        case 3:
            currentPoint = newPoint
            flash(at: newPoint)

        default:
            break
        }
    }

    private func parseCoordinateFields(_ command: String) -> CoordinateCommand {
        var result = CoordinateCommand()
        var index = command.startIndex

        while index < command.endIndex {
            let c = command[index]
            guard c == "X" || c == "Y" || c == "I" || c == "J" || c == "D" else {
                index = command.index(after: index)
                continue
            }

            let next = command.index(after: index)
            var end = next
            while end < command.endIndex {
                let nextCharacter = command[end]
                if nextCharacter == "X" || nextCharacter == "Y" ||
                    nextCharacter == "I" || nextCharacter == "J" || nextCharacter == "D" {
                    break
                }
                end = command.index(after: end)
            }

            let value = String(command[next..<end])
            switch c {
            case "X": result.x = value
            case "Y": result.y = value
            case "I": result.i = value
            case "J": result.j = value
            case "D": result.dCode = Int(value)
            default: break
            }
            index = end
        }

        return result
    }

    private func parseCoordinate(_ value: String) -> Double? {
        guard !value.isEmpty, let integer = Int(value) else { return nil }
        return Double(integer) / pow(10.0, Double(formatDecimalDigits)) * unitScale
    }

    // MARK: - Physical copper primitives

    private func stroke(from a: CGPoint, to b: CGPoint) {
        guard let apertureNumber = currentAperture,
              let aperture = apertures[apertureNumber],
              a != b else { return }

        let scale = unitScale

        switch aperture {
        case .circle(let diameter):
            let radius = diameter * scale / 2.0
            if a == b {
                add(path: circle(center: a, radius: radius))
            } else {
                add(path: capsule(from: a, to: b, radius: radius))
            }

        case .rectangle(let width, let height):
            // A rectangular Gerber aperture swept along a segment is the Minkowski
            // sum of the segment and the rectangle. For copper/toolpath purposes this
            // polygon approximation preserves the physical width and square ends.
            add(path: rectangularSweep(from: a, to: b,
                                       width: width * scale,
                                       height: height * scale))

        case .roundRect(let radius, let corners):
            // A macro aperture is not normally used for conductor strokes. If it is,
            // approximate its bounding box as a round-ended sweep.
            let xs = corners.map(\.x)
            let ys = corners.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return }
            let halfWidth = max(maxX - minX, maxY - minY) * scale / 2.0
            _ = radius
            add(path: capsule(from: a, to: b, radius: halfWidth))
        }
    }

    private func flash(at point: CGPoint) {
        guard let apertureNumber = currentAperture,
              let aperture = apertures[apertureNumber] else { return }

        switch aperture {
        case .circle(let diameter):
            add(path: circle(center: point, radius: diameter * unitScale / 2.0))

        case .rectangle(let width, let height):
            add(path: rectangle(center: point,
                                width: width * unitScale,
                                height: height * unitScale))

        case .roundRect(let radius, let corners):
            let scale = unitScale
            let centers = corners.map {
                CGPoint(x: point.x + $0.x * scale,
                        y: point.y + $0.y * scale)
            }
            let r = radius * scale

            // The macro in this KiCad output describes four corner centers. The
            // rounded rectangle is the union of four round-capped edge sweeps.
            guard centers.count == 4 else { return }
            for index in 0..<4 {
                let a = centers[index]
                let b = centers[(index + 1) % 4]
                add(path: capsule(from: a, to: b, radius: r))
            }
        }
    }

    private func finishRegion() {
        guard regionPoints.count >= 3 else {
            regionPoints.removeAll(keepingCapacity: true)
            inRegion = false
            return
        }

        var points = regionPoints
        if points.first == points.last {
            points.removeLast()
        }

        if points.count >= 3 {
            add(path: points)
        }

        regionPoints.removeAll(keepingCapacity: true)
        inRegion = false
    }

    private func add(path: [CGPoint]) {
        guard path.count >= 3 else { return }
        switch polarity {
        case .dark: positivePaths.append(path)
        case .clear: negativePaths.append(path)
        }
    }

    // MARK: - Polygon primitives

    private func circle(center: CGPoint, radius: Double, segments: Int = 48) -> [CGPoint] {
        guard radius > 0 else { return [] }
        return (0..<segments).map { index in
            let angle = Double(index) * 2.0 * .pi / Double(segments)
            return CGPoint(x: center.x + cos(angle) * radius,
                           y: center.y + sin(angle) * radius)
        }
    }

    private func capsule(from a: CGPoint, to b: CGPoint, radius: Double,
                         arcSegments: Int = 16) -> [CGPoint] {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0, radius > 0 else { return [] }

        let nx = -dy / length
        let ny = dx / length
        let angle = atan2(dy, dx)

        var result: [CGPoint] = []
        result.reserveCapacity(arcSegments * 2 + 2)

        // Semicircle around B.
        for i in 0...arcSegments {
            let theta = angle - .pi / 2.0 + Double(i) * .pi / Double(arcSegments)
            result.append(CGPoint(x: b.x + cos(theta) * radius,
                                  y: b.y + sin(theta) * radius))
        }

        // Semicircle around A.
        for i in 0...arcSegments {
            let theta = angle + .pi / 2.0 + Double(i) * .pi / Double(arcSegments)
            result.append(CGPoint(x: a.x + cos(theta) * radius,
                                  y: a.y + sin(theta) * radius))
        }

        _ = nx
        _ = ny
        return result
    }

    private func rectangularSweep(from a: CGPoint, to b: CGPoint,
                                  width: Double, height: Double) -> [CGPoint] {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return [] }

        let ux = dx / length
        let uy = dy / length
        let nx = -uy
        let ny = ux
        let hw = width / 2.0
        let hh = height / 2.0

        // Conservative physical sweep: a rectangle centered on the line with the
        // aperture's larger dimension across the motion direction.
        let halfAcross = max(hw, hh)
        let halfAlong = min(hw, hh)

        return [
            CGPoint(x: a.x - ux * halfAlong + nx * halfAcross,
                    y: a.y - uy * halfAlong + ny * halfAcross),
            CGPoint(x: b.x + ux * halfAlong + nx * halfAcross,
                    y: b.y + uy * halfAlong + ny * halfAcross),
            CGPoint(x: b.x + ux * halfAlong - nx * halfAcross,
                    y: b.y + uy * halfAlong - ny * halfAcross),
            CGPoint(x: a.x - ux * halfAlong - nx * halfAcross,
                    y: a.y - uy * halfAlong - ny * halfAcross)
        ]
    }

    private func rectangle(center: CGPoint, width: Double, height: Double) -> [CGPoint] {
        let hw = width / 2.0
        let hh = height / 2.0
        return [
            CGPoint(x: center.x - hw, y: center.y - hh),
            CGPoint(x: center.x + hw, y: center.y - hh),
            CGPoint(x: center.x + hw, y: center.y + hh),
            CGPoint(x: center.x - hw, y: center.y + hh)
        ]
    }

    // MARK: - Boolean merge

    private func mergedEntities() -> [DXF.Entity] {
        guard !positivePaths.isEmpty else { return [] }

        var overlay = CGOverlay()

        for path in positivePaths {
            overlay.add(path: path, type: .subject)
        }

        for path in negativePaths {
            overlay.add(path: path, type: .clip)
        }

        let graph = overlay.buildGraph()
        var shapes: [[[CGPoint]]]

        if negativePaths.isEmpty {
            shapes = graph.extractShapes(overlayRule: .union)

            // A positive copper union must not contain a second contour completely
            // inside another positive contour. This can happen with overlay graphs
            // when one primitive (for example a thin trace) is wholly contained by
            // a larger copper pour/pad. Such a contour is not an additional boundary
            // for machining; it is already copper.
            //
            // Do this cleanup ONLY for the positive union. For a difference result,
            // an inner contour can be a real hole and therefore must be preserved.
            shapes = shapes.map { shape in
                let paths = shape.filter { $0.count >= 3 }
                return paths.filter { candidate in
                    guard !candidate.isEmpty else { return false }
                    return !paths.contains { other in
                        guard !samePath(candidate, other),
                              polygonArea(other) > polygonArea(candidate) else {
                            return false
                        }
                        // Require the whole candidate contour to be contained, not
                        // merely one vertex. This prevents a genuinely intersecting
                        // contour from being mistaken for an enclosed one.
                        return candidate.allSatisfy { point($0, isInside: other) }
                    }
                }
            }
        } else {
            shapes = graph.extractShapes(overlayRule: .difference)
        }

        var entities: [DXF.Entity] = []
        entities.reserveCapacity(shapes.reduce(0) { $0 + $1.count })

        for shape in shapes {
            for path in shape where path.count >= 3 {
                let vertices = path.map { DXF.PolyVertex(DXF.Point($0.x, $0.y)) }
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

        return entities
    }

    // MARK: - Positive-union contour cleanup

    private func polygonArea(_ path: [CGPoint]) -> Double {
        guard path.count >= 3 else { return 0 }
        var sum = 0.0
        for index in path.indices {
            let next = path.index(after: index) == path.endIndex
                ? path.startIndex
                : path.index(after: index)
            sum += path[index].x * path[next].y - path[next].x * path[index].y
        }
        return abs(sum) * 0.5
    }

    private func samePath(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        return polygonArea(a) == polygonArea(b) && a[0] == b[0]
    }

    private func point(_ point: CGPoint, isInside polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }

        // Ray-casting test. Points on the boundary are considered inside so a
        // coincident/contained trace cannot survive as a redundant contour.
        var inside = false
        var previous = polygon[polygon.count - 1]

        for current in polygon {
            let cross = (current.x - previous.x) * (point.y - previous.y) -
                        (current.y - previous.y) * (point.x - previous.x)
            let minX = min(previous.x, current.x)
            let maxX = max(previous.x, current.x)
            let minY = min(previous.y, current.y)
            let maxY = max(previous.y, current.y)
            let epsilon = 1.0e-9

            if abs(cross) <= epsilon &&
                point.x >= minX - epsilon && point.x <= maxX + epsilon &&
                point.y >= minY - epsilon && point.y <= maxY + epsilon {
                return true
            }

            if (current.y > point.y) != (previous.y > point.y) {
                let xAtY = (previous.x - current.x) *
                           (point.y - current.y) /
                           (previous.y - current.y) + current.x
                if point.x < xAtY {
                    inside.toggle()
                }
            }
            previous = current
        }

        return inside
    }
}
