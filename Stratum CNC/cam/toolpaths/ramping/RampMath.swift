//
//  RampMath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

/// Centralised, best-effort geometry so the small preview cards, the large
/// detail view and the caption text all agree on the same numbers.
enum RampMath {
    static func clampedAngle(_ angle: Double, min minValue: Double = 1, max maxValue: Double = 89) -> Double {
        min(max(angle, minValue), maxValue)
    }

    /// Vertical depth reached over the horizontal ramp `length`, for a given `angle`.
    static func linearDepth(angle: Double, length: Double) -> Double {
        let a = clampedAngle(angle)
        let l = max(length, 0.1)
        return l * tan(a * .pi / 180)
    }

    /// Rough number of helix turns needed to plunge — steeper angle, fewer turns.
    static func helixTurns(angle: Double) -> Int {
        let a = clampedAngle(angle, min: 2, max: 90)
        return min(max(Int((90 / a).rounded()), 1), 8)
    }

    /// Rough number of zig-zag passes across a nominal channel, driven by angle and length.
    static func zigZagPasses(angle: Double, length: Double, channelHeight: Double = 40) -> Int {
        let a = clampedAngle(angle, min: 5, max: 85)
        let l = max(length, 0.1)
        let toothRun = channelHeight / tan(a * .pi / 180)
        return min(max(Int((l / max(toothRun, 4)).rounded(.up)), 1), 10)
    }

    /// Horizontal ramp length required to reach `stepdown` at a given `angle`.
    /// This is the real driving relationship: stepdown is the constraint,
    /// angle sets the slope, and this is how much length that slope needs.
    static func linearRequiredLength(angle: Double, stepdown: Double) -> Double {
        let a = clampedAngle(angle)
        let d = max(stepdown, 0.01)
        return d / tan(a * .pi / 180)
    }

    /// The actual outcome of a linear ramp given angle, available length, and
    /// the stepdown it must never exceed.
    /// - If `length` is enough, the ramp reaches full `stepdown` depth using
    ///   only the portion of `length` it needs (`usedLength <= length`).
    /// - If `length` falls short, the ramp uses all of it but only reaches a
    ///   partial depth — `reachesStepdown` is false, which callers should
    ///   surface as a warning rather than silently under-cutting.
    static func linearRampOutcome(angle: Double, length: Double, stepdown: Double) -> (usedLength: Double, depth: Double, reachesStepdown: Bool) {
        let a = clampedAngle(angle)
        let l = max(length, 0.1)
        let d = max(stepdown, 0.01)
        let requiredLength = d / tan(a * .pi / 180)
        if l >= requiredLength {
            return (requiredLength, d, true)
        } else {
            let depth = l * tan(a * .pi / 180)
            return (l, depth, false)
        }
    }
}

// MARK: - Path-following helper (drives the animated tool dot)

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

extension CGVector {
    var normalized: CGVector {
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return .zero }
        return CGVector(dx: dx / len, dy: dy / len)
    }
}

/// Returns the point on a polyline at normalised `phase` (0...1), looping.
func point(along points: [CGPoint], phase: CGFloat) -> CGPoint {
    guard points.count > 1 else { return points.first ?? .zero }
    let segmentLengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
    let total = segmentLengths.reduce(0, +)
    guard total > 0 else { return points[0] }
    var target = phase.truncatingRemainder(dividingBy: 1) * total
    for (index, segmentLength) in segmentLengths.enumerated() {
        if target <= segmentLength {
            let t = segmentLength > 0 ? target / segmentLength : 0
            let p0 = points[index]
            let p1 = points[index + 1]
            return CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t)
        }
        target -= segmentLength
    }
    return points.last!
}

func phase(for date: Date, cycleDuration: Double) -> CGFloat {
    let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)
    return CGFloat(t / cycleDuration)
}

/// Small triangular arrow indicating direction of travel, tip at `point`.
func arrowhead(at point: CGPoint, direction: CGVector, length: CGFloat = 7, width: CGFloat = 5) -> Path {
    let normalized = direction.normalized
    let backX = point.x - normalized.dx * length
    let backY = point.y - normalized.dy * length
    let perpX = -normalized.dy * (width / 2)
    let perpY = normalized.dx * (width / 2)
    var path = Path()
    path.move(to: point)
    path.addLine(to: CGPoint(x: backX + perpX, y: backY + perpY))
    path.addLine(to: CGPoint(x: backX - perpX, y: backY - perpY))
    path.closeSubpath()
    return path
}
