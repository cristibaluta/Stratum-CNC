//
//  BezierPathFlattener.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import AppKit

enum BezierPathFlattener {

    /// Flattens an array of NSBezierPath into an array of subpaths, where each
    /// subpath is an array of NSPoint forming a polyline approximation of the
    /// original curves.
    ///
    /// Each `moveTo` in the source path(s) starts a new subpath in the result.
    /// A `closePath` element appends the subpath's starting point to close the loop.
    ///
    /// - Parameters:
    ///   - paths: the source paths (e.g. parsed from an SVG)
    ///   - tolerance: max allowed deviation (in the path's own coordinate units)
    ///     between the flattened polyline and the true curve. Smaller = smoother
    ///     but more points. 0.05–0.2 is a reasonable starting range if your units
    ///     are millimeters; scale accordingly for points/pixels.
    /// - Returns: array of subpaths, each an array of points in order.
    static func flatten(_ paths: [NSBezierPath], tolerance: CGFloat = 0.1) -> [[NSPoint]] {
        var allSubpaths: [[NSPoint]] = []

        for path in paths {
            allSubpaths.append(contentsOf: flattenSinglePath(path, tolerance: tolerance))
        }

        return allSubpaths
    }

    // MARK: - Single path handling

    private static func flattenSinglePath(_ path: NSBezierPath, tolerance: CGFloat) -> [[NSPoint]] {
        var subpaths: [[NSPoint]] = []
        var currentSubpath: [NSPoint] = []

        var currentPoint = NSPoint.zero
        var subpathStart = NSPoint.zero

        let pointsBuffer = NSPointArray.allocate(capacity: 3)
        defer { pointsBuffer.deallocate() }

        for i in 0..<path.elementCount {
            let elementType = path.element(at: i, associatedPoints: pointsBuffer)

            switch elementType {
            case .moveTo:
                // Starting a new subpath — flush the previous one if it has content.
                if currentSubpath.count > 1 {
                    subpaths.append(currentSubpath)
                }
                currentPoint = pointsBuffer[0]
                subpathStart = currentPoint
                currentSubpath = [currentPoint]

            case .lineTo:
                let endPoint = pointsBuffer[0]
                currentSubpath.append(endPoint)
                currentPoint = endPoint

            case .curveTo:
                let control1 = pointsBuffer[0]
                let control2 = pointsBuffer[1]
                let endPoint = pointsBuffer[2]

                let flattenedPoints = flattenCubicBezierAdaptive(
                    p0: currentPoint,
                    p1: control1,
                    p2: control2,
                    p3: endPoint,
                    tolerance: tolerance
                )
                // flattenedPoints excludes the starting point (already in currentSubpath)
                currentSubpath.append(contentsOf: flattenedPoints)
                currentPoint = endPoint

            case .closePath:
                currentSubpath.append(subpathStart)
                currentPoint = subpathStart

            case .cubicCurveTo, .quadraticCurveTo:
                // Present on newer AppKit versions when paths are built with the
                // typed curve APIs. Handle the cubic case the same as curveTo;
                // quadratic is rare from SVG import (SVG quadratics are usually
                // already converted to cubic by the parser) but handled for safety.
                if elementType == .cubicCurveTo {
                    let control1 = pointsBuffer[0]
                    let control2 = pointsBuffer[1]
                    let endPoint = pointsBuffer[2]
                    let flattenedPoints = flattenCubicBezierAdaptive(
                        p0: currentPoint, p1: control1, p2: control2, p3: endPoint,
                        tolerance: tolerance
                    )
                    currentSubpath.append(contentsOf: flattenedPoints)
                    currentPoint = endPoint
                } else {
                    let control = pointsBuffer[0]
                    let endPoint = pointsBuffer[1]
                    // Promote quadratic to cubic control points, then flatten.
                    let c1 = NSPoint(
                        x: currentPoint.x + 2.0/3.0 * (control.x - currentPoint.x),
                        y: currentPoint.y + 2.0/3.0 * (control.y - currentPoint.y)
                    )
                    let c2 = NSPoint(
                        x: endPoint.x + 2.0/3.0 * (control.x - endPoint.x),
                        y: endPoint.y + 2.0/3.0 * (control.y - endPoint.y)
                    )
                    let flattenedPoints = flattenCubicBezierAdaptive(
                        p0: currentPoint, p1: c1, p2: c2, p3: endPoint,
                        tolerance: tolerance
                    )
                    currentSubpath.append(contentsOf: flattenedPoints)
                    currentPoint = endPoint
                }

            @unknown default:
                break
            }
        }

        if currentSubpath.count > 1 {
            subpaths.append(currentSubpath)
        }

        return subpaths
    }

    // MARK: - Adaptive cubic bezier flattening

    /// Recursively subdivides a cubic bezier until each segment is flat enough
    /// (within `tolerance`), returning the resulting points EXCLUDING p0
    /// (so callers can directly append to an existing point list).
    private static func flattenCubicBezierAdaptive(
        p0: NSPoint, p1: NSPoint, p2: NSPoint, p3: NSPoint,
        tolerance: CGFloat,
        maxDepth: Int = 24
    ) -> [NSPoint] {
        var result: [NSPoint] = []
        subdivide(p0: p0, p1: p1, p2: p2, p3: p3, tolerance: tolerance, depth: 0, maxDepth: maxDepth, output: &result)
        result.append(p3)
        return result
    }

    private static func subdivide(
        p0: NSPoint, p1: NSPoint, p2: NSPoint, p3: NSPoint,
        tolerance: CGFloat, depth: Int, maxDepth: Int,
        output: inout [NSPoint]
    ) {
        if depth >= maxDepth || isFlatEnough(p0: p0, p1: p1, p2: p2, p3: p3, tolerance: tolerance) {
            return
        }

        // De Casteljau subdivision at t = 0.5
        let p01 = midpoint(p0, p1)
        let p12 = midpoint(p1, p2)
        let p23 = midpoint(p2, p3)
        let p012 = midpoint(p01, p12)
        let p123 = midpoint(p12, p23)
        let p0123 = midpoint(p012, p123)

        // Left half
        subdivide(p0: p0, p1: p01, p2: p012, p3: p0123, tolerance: tolerance, depth: depth + 1, maxDepth: maxDepth, output: &output)
        output.append(p0123)
        // Right half
        subdivide(p0: p0123, p1: p123, p2: p23, p3: p3, tolerance: tolerance, depth: depth + 1, maxDepth: maxDepth, output: &output)
    }

    /// Flatness test: checks how far the interior control points deviate from
    /// the chord p0->p3. If both are within tolerance, the curve is "flat enough"
    /// to be approximated by the straight line p0->p3.
    private static func isFlatEnough(p0: NSPoint, p1: NSPoint, p2: NSPoint, p3: NSPoint, tolerance: CGFloat) -> Bool {
        let d1 = perpendicularDistance(point: p1, lineStart: p0, lineEnd: p3)
        let d2 = perpendicularDistance(point: p2, lineStart: p0, lineEnd: p3)
        return max(d1, d2) <= tolerance
    }

    private static func perpendicularDistance(point: NSPoint, lineStart: NSPoint, lineEnd: NSPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared < .ulpOfOne {
            // Degenerate line (start == end); fall back to distance from the point.
            let ddx = point.x - lineStart.x
            let ddy = point.y - lineStart.y
            return (ddx * ddx + ddy * ddy).squareRoot()
        }

        // Cross product magnitude / line length = perpendicular distance.
        let cross = abs(dx * (lineStart.y - point.y) - dy * (lineStart.x - point.x))
        return cross / lengthSquared.squareRoot()
    }

    private static func midpoint(_ a: NSPoint, _ b: NSPoint) -> NSPoint {
        NSPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

// MARK: - Usage example

/*
let svgPaths: [NSBezierPath] = ... // your parsed SVG paths

// tolerance in the same units as your path coordinates (e.g. points, or mm
// if you've already scaled). 0.1 is a good starting point for mm.
let subpaths = BezierPathFlattener.flatten(svgPaths, tolerance: 0.1)

for subpath in subpaths {
    print("Subpath with \(subpath.count) points")
    // Feed this into your G-code move-generation step next.
}
*/
