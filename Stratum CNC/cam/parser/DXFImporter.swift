//
//  SVGImporter 2.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 06/09/2026.
//

import Foundation
import SwiftDXF
import AppKit
import CoreText

class DXFImporter: Importer {

    private let factory = ObjectFactory()

    func parse(url: URL) -> D2_Object? {
        
        guard let dwg = try? DXF.read(contentsOf: url) else {
            return nil
        }
        print(dwg.version)          // e.g. "AC1009" (R12)
        print(dwg.counts.total)     // entities read
        print(dwg.bounds as Any)
        var w = 100.0
        var h = 297.0
        var position = CGPoint.zero
        if let bounds = dwg.bounds {
            w = bounds.max.x - bounds.min.x
            h = bounds.max.y - bounds.min.y
            position = CGPoint(x: bounds.min.x, y: bounds.min.y)
        }

        var paths: [STBezierPath] = []
        for entity in dwg.entities {
            print(entity)
            if let path = entity.bezierPath() {
                paths.append(path)
            }
        }
        let obj = D2_Object(name: url.lastPathComponent,
                            paths: paths,
                            position: position,
                            originalSize: CGSize(width: w, height: h),
                            width: w)
        return obj
    }
}

extension DXF.Entity {

    func bezierPath() -> STBezierPath? {
        switch self {

        case let .line(a, b, _, _):
            let path = STBezierPath()
            path.move(to: a.cgPoint)
            path.line(to: b.cgPoint)
            return path

        case let .circle(center, radius, _, _):
            return STBezierPath(
                ovalIn: NSRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )

        case let .arc(center, radius, startDeg, endDeg, _, _):
            let path = STBezierPath()

            let start = CGFloat(startDeg)
            var end = CGFloat(endDeg)

            // DXF arcs sweep CCW. Normalize the end so we
            // don't accidentally get a negative sweep.
            while end < start {
                end += 360
            }

            let startPoint = CGPoint(
                x: center.x + radius * cos(startDeg * .pi / 180),
                y: center.y + radius * sin(startDeg * .pi / 180)
            )
            path.move(to: startPoint)
            path.appendArc(withCenter: center.cgPoint, radius: radius, startAngle: start, endAngle: end, clockwise: false)

            return path

        case let .ellipse(center, majorAxis, ratio, startParam, endParam, _, _):
            return ellipsePath(
                center: center,
                majorAxis: majorAxis,
                ratio: ratio,
                startParam: startParam,
                endParam: endParam
            )

        case let .point(at, _, _):
            // Represent a DXF POINT as a very small cross.
            let size = 1.0
            let path = STBezierPath()

            path.move(to: CGPoint(x: at.x - size, y: at.y))
            path.line(to: CGPoint(x: at.x + size, y: at.y))

            path.move(to: CGPoint(x: at.x, y: at.y - size))
            path.line(to: CGPoint(x: at.x, y: at.y + size))

            return path

        case let .text(at, height, rotationDeg, string, _, _):
            return textPath(
                at: at,
                height: height,
                rotationDeg: rotationDeg,
                string: string
            )

        case let .polyline(vertices, closed, _, _):
            return polylinePath(vertices: vertices, closed: closed)

        case .dimension:
            // SwiftDXF intentionally doesn't expose rendered
            // dimension glyph geometry.
            return nil
        }
    }
}

extension DXF.Point {
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

private func polylinePath(vertices: [DXF.PolyVertex], closed: Bool) -> STBezierPath? {

    guard vertices.count >= 2 else {
        return nil
    }

    let path = STBezierPath()

    path.move(to: vertices[0].point.cgPoint)

    let segmentCount = closed
        ? vertices.count
        : vertices.count - 1

    for i in 0..<segmentCount {

        let current = vertices[i]
        let next = vertices[(i + 1) % vertices.count]

        let a = current.point
        let b = next.point

        let bulge = current.bulge

        if abs(bulge) < 1e-12 {
            // Straight segment
            path.line(to: b.cgPoint)
        } else {
            appendBulgeArc(
                to: path,
                from: a,
                to: b,
                bulge: bulge
            )
        }
    }

    if closed {
        path.close()
    }

    return path
}

private func appendBulgeArc(
    to path: STBezierPath,
    from a: SwiftDXF.DXF.Point,
    to b: SwiftDXF.DXF.Point,
    bulge: Double
) {
    let dx = b.x - a.x
    let dy = b.y - a.y

    let chord = hypot(dx, dy)

    guard chord > 1e-12 else {
        return
    }

    // Included angle:
    //
    // bulge = tan(theta / 4)
    //
    let theta = 4.0 * atan(bulge)

    let halfChord = chord / 2.0

    // Radius from chord and included angle.
    let radius = halfChord / abs(sin(theta / 2.0))

    // Midpoint of chord
    let mx = (a.x + b.x) / 2.0
    let my = (a.y + b.y) / 2.0

    // Unit perpendicular to chord.
    let nx = -dy / chord
    let ny = dx / chord

    // Distance from midpoint to center.
    let centerDistance =
        halfChord / tan(abs(theta) / 2.0)

    // Bulge sign determines which side of the chord
    // the center lies on.
    let sign = bulge >= 0 ? 1.0 : -1.0

    let cx = mx + nx * centerDistance * sign
    let cy = my + ny * centerDistance * sign

    let center = CGPoint(x: cx, y: cy)

    let startAngle = atan2(a.y - cy, a.x - cx)
    let endAngle = atan2(b.y - cy, b.x - cx)

    let startDegrees = startAngle * 180.0 / .pi
    let endDegrees = endAngle * 180.0 / .pi

    path.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: CGFloat(startDegrees),
        endAngle: CGFloat(endDegrees),
        clockwise: bulge < 0
    )
}

private func ellipsePath(
    center: SwiftDXF.DXF.Point,
    majorAxis: SwiftDXF.DXF.Point,
    ratio: Double,
    startParam: Double,
    endParam: Double
) -> STBezierPath {

    let majorRadius = hypot(
        majorAxis.x,
        majorAxis.y
    )

    let minorRadius = majorRadius * ratio

    let rotation = atan2(
        majorAxis.y,
        majorAxis.x
    )

    let path = STBezierPath()

    let sampleCount = max(
        32,
        Int(abs(endParam - startParam) * 32 / (2 * .pi))
    )

    for i in 0...sampleCount {

        let t =
            startParam +
            (endParam - startParam) *
            Double(i) /
            Double(sampleCount)

        // Parametric ellipse before rotation.
        let x = majorRadius * cos(t)
        let y = minorRadius * sin(t)

        // Rotate by major-axis angle.
        let xr =
            x * cos(rotation) -
            y * sin(rotation)

        let yr =
            x * sin(rotation) +
            y * cos(rotation)

        let point = CGPoint(
            x: center.x + xr,
            y: center.y + yr
        )

        if i == 0 {
            path.move(to: point)
        } else {
            path.line(to: point)
        }
    }

    return path
}

private func textPath(
    at point: SwiftDXF.DXF.Point,
    height: Double,
    rotationDeg: Double,
    string: String) -> STBezierPath {

    let path = STBezierPath()

    let font = NSFont.systemFont(ofSize: height)

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font
    ]

    let attributed = NSAttributedString(
        string: string,
        attributes: attributes
    )

    let line = CTLineCreateWithAttributedString(
        attributed as CFAttributedString
    )

    let runs = CTLineGetGlyphRuns(line) as NSArray

    // This is primarily useful if you actually need
    // the text outline. For CNC, text should generally
    // be converted to glyph outlines separately.
    _ = runs

    return path
}
