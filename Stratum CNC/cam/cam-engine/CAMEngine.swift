//
//  CAMEngine.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 10.09.2026.
//

import Foundation
import simd
import SwiftDXF

/// Standardized primitives understood by standard CNC controllers
enum Segment: Sendable {
    case line(start: CGPoint, end: CGPoint)
    /// Sweep arc in XY plane. Angles in radians CCW from positive X-axis.
    case arc(center: CGPoint, radius: Double, startAngle: Double, endAngle: Double, isCCW: Bool)
}

// MARK: - Settings & Metadata

struct ToolParams: Sendable {
    public var id: UUID
    public var diameter: Double
    public var stepdown: Double // Max Z cut depth per pass

    public init(id: UUID = UUID(), diameter: Double, stepdown: Double) {
        self.id = id
        self.diameter = diameter
        self.stepdown = stepdown
    }
}

struct MachineSettings: Sendable {
    public var feedRate: Double   // XY cut speed
    public var plungeRate: Double // Z depth speed
    public var targetDepth: Double // Total cut depth (negative Z)
    public var safeZ: Double      // Retraction clearance height (positive Z)

    public init(feedRate: Double, plungeRate: Double, targetDepth: Double, safeZ: Double) {
        self.feedRate = feedRate
        self.plungeRate = plungeRate
        self.targetDepth = targetDepth
        self.safeZ = safeZ
    }
}

// MARK: - Output Toolpath Models

enum MotionType: Sendable {
    case rapid
    case linear
    case arcCW(center: CGPoint)
    case arcCCW(center: CGPoint)
}

struct Waypoint: Sendable {
    public var position: SIMD3<Double> // X, Y, Z
    public var motion: MotionType
    public var feedRate: Double
}

struct ToolpathPass: Sendable {
    public var depthZ: Double
    public var waypoints: [Waypoint]
}

struct OutputToolpath: Sendable {
    public var sourceContourID: UUID
    public var passes: [ToolpathPass]
}

final class CAMEngine {

    init() {}

    /// Generates engraving toolpaths following the input contours exactly
    func generateEngraving(from contours: [Contour], tool: ToolParams, settings: MachineSettings) -> [OutputToolpath] {

        var results: [OutputToolpath] = []

        for contour in contours {
            // 1. Normalize DXF Entities into linear/arc segments (handling reversed flag)
            let baseSegments = linearize(contour: contour)
            guard !baseSegments.isEmpty else {
                continue
            }

            // 2. Calculate Z depth passes based on tool stepdown
            let zDepths = calculateZPasses(targetDepth: settings.targetDepth, stepdown: tool.stepdown)

            // 3. Build waypoints per pass
            var passes: [ToolpathPass] = []
            for z in zDepths {
                let waypoints = buildWaypoints(for: baseSegments, atZ: z, settings: settings)
                passes.append(ToolpathPass(depthZ: z, waypoints: waypoints))
            }

            results.append(OutputToolpath(sourceContourID: UUID(), passes: passes))
        }

        return results
    }

    // MARK: - Internal Helper Steps

    private func linearize(contour: Contour) -> [Segment] {
        var segments: [Segment] = []
        
        for chained in contour.entities {
            let extracted = convert(entity: chained.entity, reversed: chained.reversed)
            segments.append(contentsOf: extracted)
        }
        
        return segments
    }

    /// Converts a raw DXF entity into normalized CNC path primitives (`Segment`).
    /// - Parameters:
    ///   - entity: The source DXF entity from the contour chain.
    ///   - reversed: `true` if EntityChainer is walking the entity backwards.
    /// - Returns: An array of linear and circular arc segments representing the cutter motion.
    public func convert(entity: DXF.Entity, reversed: Bool) -> [Segment] {

        switch entity {
            case let .line(a, b, _, _):
                let start = reversed ? b.cgPoint : a.cgPoint
                let end = reversed ? a.cgPoint : b.cgPoint
                return [.line(start: start, end: end)]

            case let .circle(center, radius, _, _):
                let centerPt = center.cgPoint
                // DXF circles map to 2x 180° arcs to ensure compatibility with standard CNC controllers
                if reversed {
                    return [
                        .arc(center: centerPt, radius: radius, startAngle: .pi, endAngle: 0, isCCW: false),
                        .arc(center: centerPt, radius: radius, startAngle: 2 * .pi, endAngle: .pi, isCCW: false)
                    ]
                } else {
                    return [
                        .arc(center: centerPt, radius: radius, startAngle: 0, endAngle: .pi, isCCW: true),
                        .arc(center: centerPt, radius: radius, startAngle: .pi, endAngle: 2 * .pi, isCCW: true)
                    ]
                }

            case let .arc(center, radius, startDeg, endDeg, _, _):
                let start = startDeg * .pi / 180.0
                var end = endDeg * .pi / 180.0

                // DXF arcs sweep CCW start -> end. Normalize end angle.
                while end < start {
                    end += 2 * .pi
                }

                let centerPt = center.cgPoint
                if reversed {
                    // Same physical arc, swept backwards (CW)
                    return [.arc(center: centerPt, radius: radius, startAngle: end, endAngle: start, isCCW: false)]
                } else {
                    return [.arc(center: centerPt, radius: radius, startAngle: start, endAngle: end, isCCW: true)]
                }

            case let .polyline(vertices, closed, _, _):
                let ordered = reversed ? reversedPolylineVertices(vertices, closed: closed) : vertices
                return segmentsFromPolyline(vertices: ordered, closed: closed)

            case let .ellipse(center, majorAxis, ratio, startParam, endParam, _, _):
                // Tessellate ellipse into tiny linear segments (G1 moves)
                return segmentsFromEllipse(
                    center: center.cgPoint,
                    majorAxis: majorAxis.cgPoint,
                    ratio: ratio,
                    startParam: startParam,
                    endParam: endParam,
                    reversed: reversed
                )

            case .point, .text, .dimension:
                // Non-machinable primitives generate no physical toolpath moves
                return []
        }
    }

    // MARK: - Polyline Helpers

    private func segmentsFromPolyline(vertices: [DXF.PolyVertex], closed: Bool) -> [Segment] {
        guard vertices.count >= 2 else { return [] }
        var segments: [Segment] = []

        let segmentCount = closed ? vertices.count : (vertices.count - 1)
        for i in 0..<segmentCount {
            let current = vertices[i]
            let next = vertices[(i + 1) % vertices.count]

            let startPt = current.point.cgPoint
            let endPt = next.point.cgPoint

            if abs(current.bulge) < 1e-12 {
                segments.append(.line(start: startPt, end: endPt))
            } else if let bulgeArc = createBulgeArc(from: startPt, to: endPt, bulge: current.bulge) {
                segments.append(bulgeArc)
            }
        }

        return segments
    }

    /// Converts a polyline bulge value into a CCW/CW arc segment.
    private func createBulgeArc(from a: CGPoint, to b: CGPoint, bulge: Double) -> Segment? {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let chord = hypot(dx, dy)

        guard chord > 1e-12 else { return nil }

        let theta = 4.0 * atan(bulge)
        let halfChord = chord / 2.0
        let radius = halfChord / abs(sin(theta / 2.0))

        let mx = (a.x + b.x) / 2.0
        let my = (a.y + b.y) / 2.0

        // Unit perpendicular vector
        let nx = -dy / chord
        let ny = dx / chord

        let centerDistance = halfChord / tan(abs(theta) / 2.0)
        let sign = bulge >= 0 ? 1.0 : -1.0

        let center = CGPoint(
            x: mx + nx * centerDistance * sign,
            y: my + ny * centerDistance * sign
        )

        let startAngle = atan2(a.y - center.y, a.x - center.x)
        let endAngle = atan2(b.y - center.y, b.x - center.x)
        let isCCW = bulge > 0

        return .arc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            isCCW: isCCW
        )
    }

    /// Reverses polyline vertex order and flips bulge signs for backward walking.
    private func reversedPolylineVertices(_ vertices: [DXF.PolyVertex], closed: Bool) -> [DXF.PolyVertex] {
        let n = vertices.count
        guard n > 1 else { return vertices }

        return (0..<n).map { i in
            let originalIndex = n - 1 - i
            let bulgeSourceIndex = originalIndex - 1
            let bulge: Double

            if bulgeSourceIndex >= 0 {
                bulge = -vertices[bulgeSourceIndex].bulge
            } else if closed {
                bulge = -vertices[n - 1].bulge
            } else {
                bulge = 0
            }

            return DXF.PolyVertex(vertices[originalIndex].point, bulge: bulge)
        }
    }

    // MARK: - Ellipse Helpers

    private func segmentsFromEllipse(
        center: CGPoint,
        majorAxis: CGPoint,
        ratio: Double,
        startParam: Double,
        endParam: Double,
        reversed: Bool
    ) -> [Segment] {
        let majorRadius = hypot(majorAxis.x, majorAxis.y)
        let minorRadius = majorRadius * ratio
        let rotation = atan2(majorAxis.y, majorAxis.x)

        let sampleCount = max(32, Int(abs(endParam - startParam) * 32 / (2 * .pi)))
        var points: [CGPoint] = []

        for i in 0...sampleCount {
            let t = startParam + (endParam - startParam) * Double(i) / Double(sampleCount)

            let x = majorRadius * cos(t)
            let y = minorRadius * sin(t)

            let xr = x * cos(rotation) - y * sin(rotation)
            let yr = x * sin(rotation) + y * cos(rotation)

            points.append(CGPoint(x: center.x + xr, y: center.y + yr))
        }

        if reversed {
            points.reverse()
        }

        var segments: [Segment] = []
        for i in 0..<(points.count - 1) {
            segments.append(.line(start: points[i], end: points[i + 1]))
        }
        return segments
    }

    /// Gives a list of passes
    private func calculateZPasses(targetDepth: Double, stepdown: Double) -> [Double] {
        let absoluteTarget = abs(targetDepth)
        let step = abs(stepdown)
        guard step > 0 else {
            return [-absoluteTarget]
        }

        var passes: [Double] = []
        var currentDepth = step
        
        // TODO: because of Double additions the final value is not our absoluteTarget
        // For target -1 and 0.1 steps it results in 11 steps instead 10
        // We need to make sure we don't waste passes like this
        // Added temporarily a margin of acceptable error
        while currentDepth < absoluteTarget - 0.001 {
            passes.append(-currentDepth)
            currentDepth += step
        }
        passes.append(-absoluteTarget)
        
        return passes
    }
    
    private func buildWaypoints(for segments: [Segment], atZ z: Double, settings: MachineSettings) -> [Waypoint] {
        var waypoints: [Waypoint] = []
        
        guard let first = segments.first else {
            return []
        }
        let startPoint = startPointOf(segment: first)
        
        // 1. Rapid move above start point at Safe Z
        waypoints.append(Waypoint(position: SIMD3(startPoint.x, startPoint.y, settings.safeZ),
                                  motion: .rapid,
                                  feedRate: settings.feedRate))
        
        // 2. Plunge down to target Z
        waypoints.append(Waypoint(position: SIMD3(startPoint.x, startPoint.y, z),
                                  motion: .linear,
                                  feedRate: settings.plungeRate))

        // 3. Trace segments along XY plane
        for segment in segments {
            switch segment {
                case .line(_, let end):
                    waypoints.append(Waypoint(position: SIMD3(end.x, end.y, z),
                                              motion: .linear,
                                              feedRate: settings.feedRate))

                case .arc(let center, let radius, _, let endAngle, let isCCW):
                    // Compute end position using radius and radian end angle
                    let endX = center.x + radius * cos(endAngle)
                    let endY = center.y + radius * sin(endAngle)
                    let motion: MotionType = isCCW ? .arcCCW(center: center) : .arcCW(center: center)

                    waypoints.append(Waypoint(position: SIMD3(endX, endY, z),
                                              motion: motion,
                                              feedRate: settings.feedRate))
            }
        }
        
        // 4. Retract back to Safe Z after contour completion
        if let lastPoint = waypoints.last?.position {
            waypoints.append(Waypoint(position: SIMD3(lastPoint.x, lastPoint.y, settings.safeZ),
                                      motion: .rapid,
                                      feedRate: settings.feedRate))
        }

        return waypoints
    }

    private func startPointOf(segment: Segment) -> CGPoint {
        switch segment {
        case .line(let start, _):
            return start
        case .arc(let center, let radius, let startAngle, _, _):
            return CGPoint(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle))
        }
    }
}
