//
//  PocketExtension.swift
//  Stratum CNC
//
//  A pocket that runs out through the edge of the part: the pocket's outline is pushed out on the
//  chosen sides, so the tool enters and leaves in the air and nothing is left standing at the edge.
//
//  Only the part of the outline that faces a chosen side AND reaches that side of the outline's
//  box is moved, by the side's length. The rest stays exactly as drawn. So:
//   - a rectangle gets longer, its corners stay square;
//   - a round end becomes a stadium (the round end slides out, nothing is stretched);
//   - a wall inside the pocket that faces the same way, but doesn't reach the edge, isn't touched.
//  The library has no polygon boolean to do this with, so it is done on the outline's vertices.
//

import Foundation
import CoreGraphics
import StratumCAM

extension SC.Contour {

    /// How close to the outline's box a wall must be to count as touching it, mm.
    private static let edgeTolerance = 0.05
    /// A wall counts as facing a side when its normal points at least this much that way (about 1°).
    private static let facingThreshold = 0.02
    /// Arcs are sampled in chords of this angle, radians (2°, like the library).
    private static let chordAngle = 2.0 * Double.pi / 180

    /// The outline pushed out by each side's length where it touches that side of its box.
    /// Returns `self` when nothing is extended, the contour is open, or it can't be read.
    func extendedOutline(by sides: FacingSides) -> SC.Contour {
        guard isClosed, !sides.isNone else {
            return self
        }
        let segments = linearizedSegments
        guard !segments.isEmpty else {
            return self
        }

        // 1. The outline as points, remembering which segment each one came from
        var points: [CGPoint] = []
        var ranges: [Range<Int>] = []
        for segment in segments {
            let start = points.count
            switch segment {
                case let .line(from, _):
                    points.append(from)

                case let .arc(center, radius, startAngle, endAngle, isCCW):
                    var sweep = endAngle - startAngle
                    if isCCW {
                        while sweep < 0 { sweep += 2 * .pi }
                    } else {
                        while sweep > 0 { sweep -= 2 * .pi }
                    }
                    let steps = max(1, Int((abs(sweep) / Self.chordAngle).rounded(.up)))
                    for step in 0..<steps {
                        let angle = startAngle + sweep * Double(step) / Double(steps)
                        points.append(CGPoint(x: center.x + radius * cos(angle),
                                              y: center.y + radius * sin(angle)))
                    }
            }
            ranges.append(start..<points.count)
        }
        let count = points.count
        guard count >= 3,
              let first = segments.first?.startPoint,
              let last = segments.last?.endPoint,
              hypot(first.x - last.x, first.y - last.y) < 0.01 else {
            return self
        }

        // 2. How far each point moves
        var shift = [CGPoint](repeating: .zero, count: count)
        let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let area = (0..<count).reduce(0.0) { sum, index in
            let a = points[index], b = points[(index + 1) % count]
            return sum + Double(a.x * b.y - b.x * a.y)
        }
        guard area != 0 else {
            return self
        }
        let orientation: Double = area > 0 ? 1 : -1

        for side in FacingSides.Side.allCases {
            let length = sides[side]
            guard length > 0 else {
                continue
            }

            // Does the wall from point `index` to the next face this side?
            func faces(_ index: Int) -> Bool {
                let a = points[index], b = points[(index + 1) % count]
                let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
                let size = hypot(dx, dy)
                guard size > 1e-9 else {
                    return false
                }
                // Outward normal; the sign of the area says which way the outline runs
                let nx = dy / size * orientation, ny = -dx / size * orientation
                let component: Double
                switch side {
                    case .left:  component = -nx
                    case .right: component = nx
                    case .front: component = -ny
                    case .back:  component = ny
                }
                return component > Self.facingThreshold
            }
            func touchesBox(_ point: CGPoint) -> Bool {
                switch side {
                    case .left:  return Double(point.x - box.minX) <= Self.edgeTolerance
                    case .right: return Double(box.maxX - point.x) <= Self.edgeTolerance
                    case .front: return Double(point.y - box.minY) <= Self.edgeTolerance
                    case .back:  return Double(box.maxY - point.y) <= Self.edgeTolerance
                }
            }

            let facing = (0..<count).map(faces)
            // Runs of walls facing the side, starting where one begins
            for begin in 0..<count where facing[begin] && !facing[(begin + count - 1) % count] {
                var vertices = [begin]
                var wall = begin
                while facing[wall] {
                    wall = (wall + 1) % count
                    vertices.append(wall)
                    if wall == begin {
                        break
                    }
                }
                guard vertices.contains(where: { touchesBox(points[$0]) }) else {
                    continue
                }
                for vertex in Set(vertices) {
                    switch side {
                        case .left:  shift[vertex].x -= CGFloat(length)
                        case .right: shift[vertex].x += CGFloat(length)
                        case .front: shift[vertex].y -= CGFloat(length)
                        case .back:  shift[vertex].y += CGFloat(length)
                    }
                }
            }
        }
        guard shift.contains(where: { $0 != .zero }) else {
            return self
        }

        // 3. Rebuild: a segment nothing moved on is kept as it was (arcs stay arcs)
        func moved(_ index: Int) -> SIMD2<Double> {
            let i = index % count
            return SIMD2(Double(points[i].x + shift[i].x), Double(points[i].y + shift[i].y))
        }
        var chain: [SC.Contour.Chained] = []
        for (segment, range) in zip(segments, ranges) {
            let isUntouched = range.allSatisfy { shift[$0] == .zero } && shift[range.upperBound % count] == .zero
            if isUntouched {
                switch segment {
                    case let .line(from, to):
                        chain.append(.init(geometry: .line(a: SIMD2(Double(from.x), Double(from.y)),
                                                           b: SIMD2(Double(to.x), Double(to.y))),
                                           reversed: false))
                    case let .arc(center, radius, startAngle, endAngle, isCCW):
                        let start = startAngle * 180 / .pi, end = endAngle * 180 / .pi
                        // The geometry always sweeps counter-clockwise; a clockwise arc is that, reversed
                        chain.append(.init(geometry: .arc(center: SIMD2(Double(center.x), Double(center.y)),
                                                          radius: radius,
                                                          startDeg: isCCW ? start : end,
                                                          endDeg: isCCW ? end : start),
                                         reversed: !isCCW))
                }
                continue
            }
            for index in range {
                chain.append(.init(geometry: .line(a: moved(index), b: moved(index + 1)), reversed: false))
            }
        }
        return SC.Contour(entities: chain, isClosed: true, islands: islands, topZ: topZ)
    }
}

extension Array where Element == SC.Contour {

    /// Pushes out only the outermost outlines. A shape that lies inside another one is an island
    /// of the pocket: it keeps its place and the pocketing clears around it.
    func extendingOutermost(by sides: FacingSides) -> [SC.Contour] {
        let outlines: [[CGPoint]] = map { contour in
            contour.linearizedSegments.map { $0.startPoint }
        }

        func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
            guard polygon.count >= 3 else {
                return false
            }
            var inside = false
            var j = polygon.count - 1
            for i in polygon.indices {
                let a = polygon[i], b = polygon[j]
                if (a.y > point.y) != (b.y > point.y),
                   point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
                j = i
            }
            return inside
        }

        return indices.map { index in
            guard let probe = outlines[index].first else {
                return self[index]
            }
            let isInsideAnother = outlines.indices.contains { other in
                other != index && contains(outlines[other], probe)
            }
            return isInsideAnother ? self[index] : self[index].extendedOutline(by: sides)
        }
    }
}
