//
//  PolygonOffset.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//

import Foundation
import CoreGraphics

enum PolygonOffset {

    /// Offsets a closed polyline by `distance` along its outward normal.
    /// Positive moves the result away from the interior (an "outside" cut);
    /// negative moves it inward (an "inside" cut).
    ///
    /// Per-edge offset-and-intersect — correct for convex and mildly concave
    /// profiles. It does not trim self-intersections that appear when
    /// `distance` exceeds a concave feature's own radius (a tight inner
    /// corner, a narrow slot). If you hit that, the real fix is a polygon-
    /// clipping pass, not more code here.
    static func offset(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        guard points.count >= 3, distance != 0 else { return points }

        var ring = points
        if let first = ring.first, let last = ring.last, ring.count > 1,
           hypot(first.x - last.x, first.y - last.y) < 1e-6 {
            ring.removeLast()
        }
        guard ring.count >= 3 else { return points }

        var area: CGFloat = 0
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            area += a.x * b.y - b.x * a.y
        }
        let isCCW = area > 0

        func outwardNormal(_ a: CGPoint, _ b: CGPoint) -> CGVector {
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 1e-9)
            let right = CGVector(dx: dy / len, dy: -dx / len)
            let left = CGVector(dx: -dy / len, dy: dx / len)
            return isCCW ? right : left
        }

        let n = ring.count
        var offsetEdges: [(p0: CGPoint, p1: CGPoint)] = []
        offsetEdges.reserveCapacity(n)
        for i in 0..<n {
            let a = ring[i]
            let b = ring[(i + 1) % n]
            let normal = outwardNormal(a, b)
            let shift = CGPoint(x: normal.dx * distance, y: normal.dy * distance)
            offsetEdges.append((CGPoint(x: a.x + shift.x, y: a.y + shift.y),
                                 CGPoint(x: b.x + shift.x, y: b.y + shift.y)))
        }

        var result: [CGPoint] = []
        result.reserveCapacity(n + 1)
        for i in 0..<n {
            let prev = offsetEdges[(i - 1 + n) % n]
            let curr = offsetEdges[i]
            if let intersection = lineIntersection(p1: prev.p0, p2: prev.p1, p3: curr.p0, p4: curr.p1) {
                result.append(intersection)
            } else {
                result.append(curr.p0) // parallel edges — the shifted endpoint is already correct
            }
        }
        result.append(result[0]) // close the ring, matching the caller's convention
        return result
    }

    private static func lineIntersection(p1: CGPoint, p2: CGPoint, p3: CGPoint, p4: CGPoint) -> CGPoint? {
        let d1x = p2.x - p1.x, d1y = p2.y - p1.y
        let d2x = p4.x - p3.x, d2y = p4.y - p3.y
        let denom = d1x * d2y - d1y * d2x
        guard abs(denom) > 1e-9 else { return nil }
        let t = ((p3.x - p1.x) * d2y - (p3.y - p1.y) * d2x) / denom
        return CGPoint(x: p1.x + d1x * t, y: p1.y + d1y * t)
    }
}
