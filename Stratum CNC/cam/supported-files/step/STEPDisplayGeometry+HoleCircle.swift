//
//  HoleCircle.swift
//  Stratum CNC
//
//  Holes drilled along Z, found from the model's circles. A hole is a cylinder wall: a circle at
//  its top and the same circle (same centre and diameter) at its bottom. Holes are alike when they
//  have the same diameter and the same depth, i.e. the same distance between those two circles.
//  A circle with no partner (a cone bottom, say) is compared by its own height instead.
//
//  A circle cut into two arcs by the CAD export is not recognised.
//

import Foundation
import simd
import SwiftSTEP

extension STEPDisplayGeometry {

    /// A full circle in a horizontal plane: the rim of a hole.
    struct HoleCircle: Sendable {
        let id: STEP.EdgeID
        let center: SIMD3<Float>
        let diameter: Float
    }

    /// Which end of its hole a circle is.
    private enum HoleEnd { case top, bottom, alone }

    private struct AxisKey: Hashable { let x: Int32, y: Int32, diameter: Int32 }

    private static let holeTolerance: Float = 0.01

    private static func axisKey(_ c: HoleCircle) -> AxisKey {
        AxisKey(x: Int32((c.center.x / holeTolerance).rounded()),
                y: Int32((c.center.y / holeTolerance).rounded()),
                diameter: Int32((c.diameter / holeTolerance).rounded()))
    }

    /// Every circle of the model that lies flat, so can be the rim of a hole drilled from above.
    func holeCircles(hiddenBodies: Set<STEP.BodyID> = []) -> [HoleCircle] {
        var circles: [HoleCircle] = []
        for body in bodies where !hiddenBodies.contains(body.id) {
            for edge in body.edges {
                let measure = Self.measure(polyline: Self.polyline(of: edge, in: body))
                guard measure.kind == .circle, let center = measure.center, let normal = measure.normal,
                      let radius = measure.radius, abs(normal.z) > 0.9999 else { continue }
                circles.append(HoleCircle(id: edge.id, center: center, diameter: radius * 2))
            }
        }
        return circles
    }

    /// For a circle: the other circle of its hole (same centre and diameter, nearest in height),
    /// and which end this one is.
    private func partner(of circle: HoleCircle, in groups: [AxisKey: [HoleCircle]])
        -> (end: HoleEnd, other: HoleCircle?, depth: Float?) {
        let others = (groups[Self.axisKey(circle)] ?? []).filter {
            $0.id != circle.id && abs($0.center.z - circle.center.z) > Self.holeTolerance
        }
        guard let nearest = others.min(by: {
            abs($0.center.z - circle.center.z) < abs($1.center.z - circle.center.z)
        }) else { return (.alone, nil, nil) }
        return (nearest.center.z < circle.center.z ? .top : .bottom, nearest,
                abs(nearest.center.z - circle.center.z))
    }

    /// The holes like the ones the circles `ids` belong to: the same diameter and depth, and the
    /// same end of the hole, so a hole is never picked twice. Does not include `ids`.
    func similarHoles(to ids: Set<STEP.EdgeID>, hiddenBodies: Set<STEP.BodyID> = []) -> Set<STEP.EdgeID> {
        let circles = holeCircles(hiddenBodies: hiddenBodies)
        var groups: [AxisKey: [HoleCircle]] = [:]
        for circle in circles { groups[Self.axisKey(circle), default: []].append(circle) }

        let selected = circles.filter { ids.contains($0.id) }.map { ($0, partner(of: $0, in: groups)) }
        guard !selected.isEmpty else { return [] }

        var result = Set<STEP.EdgeID>()
        for circle in circles where !ids.contains(circle.id) {
            let candidate = partner(of: circle, in: groups)
            for (reference, info) in selected {
                guard abs(circle.diameter - reference.diameter) <= Self.holeTolerance,
                      candidate.end == info.end else { continue }
                let sameDepth: Bool
                if let depth = candidate.depth, let referenceDepth = info.depth {
                    sameDepth = abs(depth - referenceDepth) <= Self.holeTolerance
                } else {
                    sameDepth = candidate.depth == nil && info.depth == nil
                        && abs(circle.center.z - reference.center.z) <= Self.holeTolerance
                }
                if sameDepth { result.insert(circle.id); break }
            }
        }
        return result
    }

    /// For each circle of `ids` that is the top of a hole: the circle at the hole's bottom, so
    /// the depth of the hole can be read from it.
    func holeBottoms(of ids: Set<STEP.EdgeID>, hiddenBodies: Set<STEP.BodyID> = []) -> [STEP.EdgeID: STEP.EdgeID] {
        let circles = holeCircles(hiddenBodies: hiddenBodies)
        guard circles.contains(where: { ids.contains($0.id) }) else { return [:] }
        var groups: [AxisKey: [HoleCircle]] = [:]
        for circle in circles { groups[Self.axisKey(circle), default: []].append(circle) }

        var result: [STEP.EdgeID: STEP.EdgeID] = [:]
        for circle in circles where ids.contains(circle.id) {
            let info = partner(of: circle, in: groups)
            if info.end == .top, let bottom = info.other { result[circle.id] = bottom.id }
        }
        return result
    }
}
