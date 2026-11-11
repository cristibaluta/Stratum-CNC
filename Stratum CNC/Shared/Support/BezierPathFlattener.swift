//
//  BezierPathFlattener.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation

enum BezierPathFlattener {

    /// Flattens an array of STBezierPath into an array of subpaths, where each
    /// subpath is an array of STPoint forming a polyline approximation of the
    /// original curves.
    ///
    static func flatten(_ paths: [STBezierPath], tolerance: CGFloat = 0.1) -> [[STPoint]] {
        var allSubpaths: [[STPoint]] = []

        for path in paths {
            allSubpaths.append(contentsOf: flattenSinglePath(path, tolerance: tolerance))
        }

        return allSubpaths
    }

    // MARK: - Single path handling

    private static func flattenSinglePath(_ path: STBezierPath, tolerance: CGFloat) -> [[STPoint]] {
        var subpaths: [[STPoint]] = []
        var currentSubpath: [STPoint] = []

        var currentPoint = STPoint.zero
        var subpathStart = STPoint.zero

        for element in path.stElements {

            switch element {
            case .move(let point):
                // Starting a new subpath — flush the previous one if it has content.
                if currentSubpath.count > 1 {
                    subpaths.append(currentSubpath)
                }
                currentPoint = point
                subpathStart = point
                currentSubpath = [point]

            case .line(let endPoint):
                currentSubpath.append(endPoint)
                currentPoint = endPoint

            case .curve(let control1, let control2, let endPoint):
                // Quadratics arrive here already promoted to cubic (see `STBezierPath.stElements`).
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

            case .close:
                currentSubpath.append(subpathStart)
                currentPoint = subpathStart
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
    private static func flattenCubicBezierAdaptive(p0: STPoint, p1: STPoint, p2: STPoint, p3: STPoint,
                                                   tolerance: CGFloat,
                                                   maxDepth: Int = 24) -> [STPoint] {
        var result: [STPoint] = []
        subdivide(p0: p0, p1: p1, p2: p2, p3: p3, tolerance: tolerance, depth: 0, maxDepth: maxDepth, output: &result)
        result.append(p3)

        return result
    }

    private static func subdivide(p0: STPoint, p1: STPoint, p2: STPoint, p3: STPoint,
                                  tolerance: CGFloat, depth: Int, maxDepth: Int,
                                  output: inout [STPoint]) {

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
    private static func isFlatEnough(p0: STPoint, p1: STPoint, p2: STPoint, p3: STPoint, tolerance: CGFloat) -> Bool {
        let d1 = perpendicularDistance(point: p1, lineStart: p0, lineEnd: p3)
        let d2 = perpendicularDistance(point: p2, lineStart: p0, lineEnd: p3)

        return max(d1, d2) <= tolerance
    }

    private static func perpendicularDistance(point: STPoint, lineStart: STPoint, lineEnd: STPoint) -> CGFloat {
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

    private static func midpoint(_ a: STPoint, _ b: STPoint) -> STPoint {
        STPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

// MARK: - Usage example

/*
let svgPaths: [STBezierPath] = ... // your parsed SVG paths

// tolerance in the same units as your path coordinates (e.g. points, or mm
// if you've already scaled). 0.1 is a good starting point for mm.
let subpaths = BezierPathFlattener.flatten(svgPaths, tolerance: 0.1)

for subpath in subpaths {
    print("Subpath with \(subpath.count) points")
    // Feed this into your G-code move-generation step next.
}
*/
