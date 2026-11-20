//
//  ShapeDetail.swift
//  Stratum CNC
//
//  One selected shape (or STEP edge) of a toolpath, described for the "Selected" list in the
//  toolpath panel: what it is, how big, and how far it sits from Z0 (the top of the stock).
//

import Foundation
import CoreGraphics
import simd
import StratumCAM

struct ShapeDetail: Identifiable {

    let id = UUID()
    /// "Circle", "Arc", "Line", "Polyline", "Outline", "Edge"…
    let kind: String
    /// "Ø 3.00 mm", "R 5.00 mm · 12.40 mm long", "20.00 mm".
    let size: String
    /// Distance to Z0: "Z 0" on the stock top, "Z -3.00" below it, a range when it isn't flat.
    let z: String

    // MARK: Formatting

    private static func mm(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Z0 is the top of the stock and below it is negative, like everywhere else in the app.
    static func zText(low: Double, high: Double) -> String {
        if abs(high - low) > 0.01 {
            return "Z \(mm(low))…\(mm(high))"
        }
        return abs(low) < 0.005 ? "Z 0" : "Z \(mm(low))"
    }

    // MARK: Canvas shapes (2D, drawn flat on the stock top)

    /// The contours behind one picked shape on the canvas, in world mm.
    static func describe(_ contours: [SC.Contour]) -> ShapeDetail {
        // A 2D shape lies flat on the face the toolpath is cut on: it sits at Z0.
        let z = zText(low: 0, high: 0)

        if contours.count == 1, contours[0].entities.count == 1 {
            switch contours[0].entities[0].geometry {
                case let .circle(_, radius):
                    return ShapeDetail(kind: "Circle", size: "Ø \(mm(radius * 2)) mm", z: z)

                case let .arc(_, radius, startDeg, endDeg):
                    var sweep = endDeg - startDeg
                    while sweep < 0 {
                        sweep += 360
                    }
                    let length = radius * sweep * .pi / 180
                    return ShapeDetail(kind: "Arc", size: "R \(mm(radius)) mm · \(mm(length)) mm long", z: z)

                case let .line(a, b):
                    return ShapeDetail(kind: "Line", size: "\(mm(simd_distance(a, b))) mm", z: z)

                case let .polyline(_, closed):
                    return ShapeDetail(kind: closed ? "Closed polyline" : "Polyline",
                                       size: "\(mm(perimeter(of: contours))) mm",
                                       z: z)

                case .ellipse:
                    return ShapeDetail(kind: "Ellipse", size: "\(mm(perimeter(of: contours))) mm", z: z)

                case .point:
                    return ShapeDetail(kind: "Point", size: "–", z: z)
            }
        }
        return ShapeDetail(kind: "Outline", size: "\(mm(perimeter(of: contours))) mm", z: z)
    }

    /// Length of the whole path of the contours.
    private static func perimeter(of contours: [SC.Contour]) -> Double {
        var total = 0.0
        for segment in contours.flatMap(\.linearizedSegments) {
            switch segment {
                case let .line(start, end):
                    total += hypot(end.x - start.x, end.y - start.y)

                case let .arc(_, radius, startAngle, endAngle, isCCW):
                    var sweep = isCCW ? endAngle - startAngle : startAngle - endAngle
                    while sweep < 0 { sweep += 2 * .pi }
                    total += radius * sweep
            }
        }
        return total
    }

    // MARK: STEP edges (3D, in the toolpath's setup frame)

    /// One sampled STEP edge, in the setup's frame (Z0 = top of the stock).
    static func describeEdge(_ points: [SIMD3<Double>]) -> ShapeDetail {
        guard let first = points.first, points.count >= 2 else {
            return ShapeDetail(kind: "Edge", size: "–", z: zText(low: 0, high: 0))
        }

        var length = 0.0
        var zMin = first.z, zMax = first.z
        for i in 1..<points.count {
            length += simd_distance(points[i - 1], points[i])
            zMin = min(zMin, points[i].z)
            zMax = max(zMax, points[i].z)
        }
        let z = zText(low: zMin, high: zMax)

        if points.count == 2 {
            return ShapeDetail(kind: "Line", size: "\(mm(length)) mm", z: z)
        }

        // A flat edge that is a circle or an arc: fit a circle through three of its points and
        // accept it when all the others lie on it.
        if zMax - zMin < 0.02, points.count >= 4,
           let circle = fitCircle(points[0], points[points.count / 3], points[2 * points.count / 3]),
           points.allSatisfy({ abs(hypot($0.x - circle.x, $0.y - circle.y) - circle.radius) <= max(circle.radius * 0.005, 0.01) }) {

            let closed = simd_distance(first, points[points.count - 1]) < max(length * 1e-3, 1e-3)
            if closed {
                return ShapeDetail(kind: "Circle", size: "Ø \(mm(circle.radius * 2)) mm", z: z)
            }
            return ShapeDetail(kind: "Arc", size: "R \(mm(circle.radius)) mm · \(mm(length)) mm long", z: z)
        }
        return ShapeDetail(kind: "Edge", size: "\(mm(length)) mm long", z: z)
    }

    /// The circle through three points in XY, nil when they are in a line.
    private static func fitCircle(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> (x: Double, y: Double, radius: Double)? {

        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-9 else {
            return nil
        }
        let a2 = a.x * a.x + a.y * a.y
        let b2 = b.x * b.x + b.y * b.y
        let c2 = c.x * c.x + c.y * c.y
        let x = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
        let y = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d

        return (x, y, hypot(a.x - x, a.y - y))
    }
}
