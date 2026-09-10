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

    private func convert(entity: DXF.Entity, reversed: Bool) -> [Segment] {
        // Implement conversion from DXF.Entity to [Segment]
        // Respect start/end reversal when reversed == true
        switch entity {
            case .line(let a, let b, _, _):
                let start = reversed ? b : a
                let end = reversed ? a : b
                return [.line(start: CGPoint(x: start.x, y: start.y), end: CGPoint(x: end.x, y: end.y))]

            case .arc(let center, let radius, let startDeg, let endDeg, _, _):
                let startRad = startDeg * .pi / 180.0
                let endRad = endDeg * .pi / 180.0
                if reversed {
                    return [.arc(center: CGPoint(x: center.x, y: center.y), radius: radius, startAngle: endRad, endAngle: startRad, isCCW: false)]
                } else {
                    return [.arc(center: CGPoint(x: center.x, y: center.y), radius: radius, startAngle: startRad, endAngle: endRad, isCCW: true)]
                }

            default:
                // Tessellate polyline bulges, ellipses, and splines into line segments
                return []
        }
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
