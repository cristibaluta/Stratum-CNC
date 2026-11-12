//
//  ContourBounds.swift
//  Stratum CNC
//
//  The XY bounding box of contours, for the facing's "extend only these sides": the library
//  extends a facing's box by one length on every side, so the app builds the box itself.
//  Curves are sampled, which is as exact as the box needs to be for a facing.
//

import Foundation
import CoreGraphics
import StratumCAM

extension SC.Contour {

    /// The box around every entity of the given contours (islands lie inside their outline and
    /// don't change it). `nil` when there is nothing to measure.
    static func xyBounds(of contours: [SC.Contour]) -> CGRect? {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for contour in contours {
            for chained in contour.entities {
                for p in chained.geometry.boundaryPoints {
                    minX = min(minX, p.x); maxX = max(maxX, p.x)
                    minY = min(minY, p.y); maxY = max(maxY, p.y)
                }
            }
        }
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return nil
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension SC.Geometry {

    /// Points on the geometry that include its extremes: the ends, and for a curve the
    /// quadrant points or a fine sampling.
    fileprivate var boundaryPoints: [SIMD2<Double>] {
        switch self {
            case let .line(a, b):
                return [a, b]

            case let .circle(center, radius):
                return [SIMD2(center.x + radius, center.y), SIMD2(center.x - radius, center.y),
                        SIMD2(center.x, center.y + radius), SIMD2(center.x, center.y - radius)]

            case let .arc(center, radius, startDeg, endDeg):
                return Self.arcPoints(center: center, radius: radius, startDeg: startDeg, endDeg: endDeg)

            case let .ellipse(center, majorAxis, ratio, startParam, endParam):
                // The minor axis is the major one turned a quarter counter-clockwise, `ratio` as long.
                let minor = SIMD2(-majorAxis.y, majorAxis.x) * ratio
                var end = endParam
                while end <= startParam { end += 2 * .pi }
                let steps = 72
                return (0...steps).map { index in
                    let t = startParam + (end - startParam) * Double(index) / Double(steps)
                    return center + majorAxis * cos(t) + minor * sin(t)
                }

            case let .point(at):
                return [at]

            case let .polyline(vertices, closed):
                var points = vertices.map { $0.point }
                let count = vertices.count
                let segments = closed ? count : count - 1
                guard segments > 0 else { return points }
                for index in 0..<segments {
                    let from = vertices[index]
                    let to = vertices[(index + 1) % count]
                    guard abs(from.bulge) > 1e-12 else { continue }
                    points += Self.bulgePoints(from: from.point, to: to.point, bulge: from.bulge)
                }
                return points
        }
    }

    /// The arc's ends and the quadrant points inside its sweep (counter-clockwise from start to end).
    private static func arcPoints(center: SIMD2<Double>, radius: Double,
                                  startDeg: Double, endDeg: Double) -> [SIMD2<Double>] {
        func point(_ degrees: Double) -> SIMD2<Double> {
            let radians = degrees * .pi / 180
            return SIMD2(center.x + radius * cos(radians), center.y + radius * sin(radians))
        }
        var end = endDeg
        while end <= startDeg { end += 360 }
        var points = [point(startDeg), point(end)]
        var quadrant = (startDeg / 90).rounded(.down) * 90 + 90
        while quadrant < end {
            points.append(point(quadrant))
            quadrant += 90
        }
        return points
    }

    /// A DXF bulge segment (bulge = tan(sweep / 4), positive counter-clockwise) sampled along its arc.
    private static func bulgePoints(from p0: SIMD2<Double>, to p1: SIMD2<Double>, bulge: Double) -> [SIMD2<Double>] {
        let chord = p1 - p0
        let length = (chord.x * chord.x + chord.y * chord.y).squareRoot()
        guard length > 1e-12 else { return [] }
        // The centre is on the left of the chord for a counter-clockwise arc, on the right for a clockwise one.
        let offset = length / 2 * (1 - bulge * bulge) / (2 * bulge)
        let normal = SIMD2(-chord.y, chord.x) / length
        let center = (p0 + p1) / 2 + normal * offset
        let radius = abs(length / 2 * (1 + bulge * bulge) / (2 * bulge))
        let sweep = 4 * atan(bulge)
        let startAngle = atan2(p0.y - center.y, p0.x - center.x)
        let steps = 24
        return (0...steps).map { index in
            let angle = startAngle + sweep * Double(index) / Double(steps)
            return SIMD2(center.x + radius * cos(angle), center.y + radius * sin(angle))
        }
    }
}
