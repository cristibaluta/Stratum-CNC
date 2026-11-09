//
//  CAMHoldingTabsOverlay.swift
//  Stratum CNC
//
//  The open contour toolpath's holding tabs, drawn on the canvas along the shapes it cuts:
//  for each tab a short stretch of the outline as wide as the tab (three parallel lines, so it
//  reads thicker than the outline itself) with a tick across each end.
//
//  A tab's position is a fraction of the contour's length, counted from where the outline starts.
//  The tool really follows the outline offset by its radius, and the engine decides where it
//  starts and which way it goes, so this is an approximation drawn on the shape itself. The tab is
//  taken as centred on its position.
//

import Foundation
import CoreGraphics

enum CAMHoldingTabsOverlay {

    /// Distance of the two outer lines from the centre one, mm.
    private static let halfThickness: CGFloat = 0.3
    /// Length of the tick across each end of a tab, mm.
    private static let tickLength: CGFloat = 1.6

    /// One `RenderObject` with every tab on every shape the toolpath cuts, or none when there is
    /// nothing to draw. Each tab is drawn on each of those shapes, like the engine cuts them.
    static func renderObjects(for overlay: D2_CanvasState.HoldingTabsOverlay,
                              paths: [D2_RenderPath],
                              color: SIMD4<Float>) -> [RenderObject] {
        let targets = Set(overlay.targets)
        var points: [SIMD3<Float>] = []

        for path in paths where targets.contains(PathSelection(objectID: path.objectID, pathIndex: path.pathIndex)) {
            for outline in outlines(of: path.worldPath) {
                for tab in overlay.tabs {
                    appendTab(tab, on: outline, into: &points)
                }
            }
        }

        guard !points.isEmpty else {
            return []
        }
        return [RenderObject(points: points, color: color, primitive: .lineList)]
    }

    // MARK: Geometry

    /// A closed polyline and the distance from its start to each vertex.
    private struct Outline {
        let points: [CGPoint]
        let cumulative: [CGFloat]
        var length: CGFloat { cumulative.last ?? 0 }
    }

    /// The subpaths of a flattened world path. A contour that doesn't end where it began is
    /// closed with a straight segment, since only closed contours carry tabs.
    private static func outlines(of path: CGPath) -> [Outline] {
        var subpaths: [[CGPoint]] = []
        var current: [CGPoint] = []

        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
                case .moveToPoint:
                    if current.count > 1 {
                        subpaths.append(current)
                    }
                    current = [element.points[0]]
                case .addLineToPoint:
                    current.append(element.points[0])
                case .closeSubpath:
                    if let first = current.first {
                        current.append(first)
                    }
                default:
                    break
            }
        }
        if current.count > 1 {
            subpaths.append(current)
        }

        return subpaths.compactMap { points in
            var points = points
            if let first = points.first, let last = points.last, hypot(first.x - last.x, first.y - last.y) > 1e-6 {
                points.append(first)
            }
            var cumulative: [CGFloat] = [0]
            for i in 1..<points.count {
                cumulative.append(cumulative[i - 1] + hypot(points[i].x - points[i - 1].x,
                                                            points[i].y - points[i - 1].y))
            }
            let outline = Outline(points: points, cumulative: cumulative)
            return outline.length > 0 ? outline : nil
        }
    }

    private static func appendTab(_ tab: HoldingTabSettings, on outline: Outline, into points: inout [SIMD3<Float>]) {
        let total = outline.length
        let half = min(CGFloat(tab.width), total) / 2
        let center = CGFloat(min(max(tab.positionRatio, 0), 1)) * total
        let from = center - half
        let to = center + half

        // A tab that runs past the start of the outline continues at its other end
        if from < 0 {
            appendStretch(from: 0, to: to, on: outline, into: &points)
            appendStretch(from: total + from, to: total, on: outline, into: &points)
        } else if to > total {
            appendStretch(from: from, to: total, on: outline, into: &points)
            appendStretch(from: 0, to: to - total, on: outline, into: &points)
        } else {
            appendStretch(from: from, to: to, on: outline, into: &points)
        }

        appendTick(at: wrapped(from, in: total), on: outline, into: &points)
        appendTick(at: wrapped(to, in: total), on: outline, into: &points)
    }

    private static func wrapped(_ distance: CGFloat, in total: CGFloat) -> CGFloat {
        var d = distance.truncatingRemainder(dividingBy: total)
        if d < 0 {
            d += total
        }
        return d
    }

    /// The part of the outline between two distances from its start, as three parallel lines.
    private static func appendStretch(from: CGFloat, to: CGFloat, on outline: Outline, into points: inout [SIMD3<Float>]) {
        guard to > from else {
            return
        }
        for i in 0..<(outline.points.count - 1) {
            let c0 = outline.cumulative[i]
            let c1 = outline.cumulative[i + 1]
            guard c1 > c0, c1 > from, c0 < to else {
                continue
            }
            let a = outline.points[i]
            let b = outline.points[i + 1]
            let p0 = lerp(a, b, (max(from, c0) - c0) / (c1 - c0))
            let p1 = lerp(a, b, (min(to, c1) - c0) / (c1 - c0))
            let n = normal(from: a, to: b, length: halfThickness)

            add(p0, p1, into: &points)
            add(CGPoint(x: p0.x + n.x, y: p0.y + n.y), CGPoint(x: p1.x + n.x, y: p1.y + n.y), into: &points)
            add(CGPoint(x: p0.x - n.x, y: p0.y - n.y), CGPoint(x: p1.x - n.x, y: p1.y - n.y), into: &points)
        }
    }

    /// A short line across the outline at a distance from its start.
    private static func appendTick(at distance: CGFloat, on outline: Outline, into points: inout [SIMD3<Float>]) {
        for i in 0..<(outline.points.count - 1) {
            let c0 = outline.cumulative[i]
            let c1 = outline.cumulative[i + 1]
            guard c1 > c0, distance >= c0, distance <= c1 else {
                continue
            }
            let a = outline.points[i]
            let b = outline.points[i + 1]
            let p = lerp(a, b, (distance - c0) / (c1 - c0))
            let n = normal(from: a, to: b, length: tickLength / 2)
            add(CGPoint(x: p.x + n.x, y: p.y + n.y), CGPoint(x: p.x - n.x, y: p.y - n.y), into: &points)
            return
        }
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// A vector of the given length at a right angle to the segment.
    private static func normal(from a: CGPoint, to b: CGPoint, length: CGFloat) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let size = hypot(dx, dy)
        guard size > 0 else {
            return .zero
        }
        return CGPoint(x: -dy / size * length, y: dx / size * length)
    }

    private static func add(_ a: CGPoint, _ b: CGPoint, into points: inout [SIMD3<Float>]) {
        points.append(SIMD3<Float>(Float(a.x), Float(a.y), 0))
        points.append(SIMD3<Float>(Float(b.x), Float(b.y), 0))
    }
}
