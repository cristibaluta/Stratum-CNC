//
//  STEPEdgeTarget.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 02.11.2026.
//


import Foundation
import simd
import StratumCAM
import SwiftSTEP

/// A STEP edge a toolpath cuts. Same identity as the viewer's `STEP.EdgeID`, in a form
/// that is saved with the toolpath. Stable as long as the source file is unchanged.
struct STEPEdgeTarget: Codable, Hashable, Sendable {
    let importID: UUID
    let representationID: Int
    let bodyEntityID: Int
    /// Which placement of the part the edge belongs to (`STEP.BodyID.instance`). 0 for everything that
    /// is not an assembly's repeated part, and for projects saved before the field existed.
    let bodyInstance: Int
    let edgeEntityID: Int

    init(_ id: STEP.EdgeID) {
        importID = id.importID
        representationID = id.bodyID.representationID
        bodyEntityID = id.bodyID.entityID
        bodyInstance = id.bodyID.instance
        edgeEntityID = id.entityID
    }

    private enum CodingKeys: String, CodingKey {
        case importID, representationID, bodyEntityID, bodyInstance, edgeEntityID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        importID = try container.decode(UUID.self, forKey: .importID)
        representationID = try container.decode(Int.self, forKey: .representationID)
        bodyEntityID = try container.decode(Int.self, forKey: .bodyEntityID)
        bodyInstance = try container.decodeIfPresent(Int.self, forKey: .bodyInstance) ?? 0
        edgeEntityID = try container.decode(Int.self, forKey: .edgeEntityID)
    }

    var edgeID: STEP.EdgeID {
        STEP.EdgeID(importID: importID,
                    bodyID: STEP.BodyID(representationID: representationID, entityID: bodyEntityID,
                                        instance: bodyInstance),
                   entityID: edgeEntityID)
    }
}

/// Turns the sampled edges of a STEP model into the contours the toolpath engine takes:
/// edges are joined end to end, and a chain that comes back to its start is closed.
/// Only X and Y are used, the toolpath's depth comes from its Start Z and End Z.
///
/// The edges are the display polylines (0.01 mm chord tolerance), so arcs and circles
/// reach the engine as many short lines, like curves imported from an SVG.
enum STEPContourBuilder {

    /// Edge ends closer than this (mm) are the same point. Display coordinates are Float.
    static let joinTolerance = 0.005

    static func contours(from polylines: [[SIMD3<Double>]]) -> [SC.Contour] {
        var remaining: [[SIMD2<Double>]] = polylines.compactMap { polyline in
            var points: [SIMD2<Double>] = []
            for point in polyline {
                let flat = SIMD2<Double>(point.x, point.y)
                if let last = points.last, simd_distance(last, flat) < 1e-9 { continue }
                points.append(flat)
            }
            return points.count >= 2 ? points : nil
        }

        var chains: [[SIMD2<Double>]] = []
        while !remaining.isEmpty {
            var chain = remaining.removeFirst()
            var extended = true
            while extended, !isClosed(chain) {
                extended = false
                for index in remaining.indices {
                    let other = remaining[index]
                    if near(chain[chain.count - 1], other[0]) {
                        chain.append(contentsOf: other.dropFirst())
                    } else if near(chain[chain.count - 1], other[other.count - 1]) {
                        chain.append(contentsOf: other.reversed().dropFirst())
                    } else if near(chain[0], other[other.count - 1]) {
                        chain = other + chain.dropFirst()
                    } else if near(chain[0], other[0]) {
                        chain = Array(other.reversed()) + chain.dropFirst()
                    } else {
                        continue
                    }
                    remaining.remove(at: index)
                    extended = true
                    break
                }
            }
            chains.append(chain)
        }

        return chains.compactMap { chain in
            var points = chain
            let closed = isClosed(points)
            if closed { points[points.count - 1] = points[0] }   // no gap left at the seam
            var entities: [SC.Contour.Chained] = []
            for index in 0..<(points.count - 1) where simd_distance(points[index], points[index + 1]) > 1e-9 {
                entities.append(SC.Contour.Chained(geometry: .line(a: points[index], b: points[index + 1]),
                                                   reversed: false))
            }
            return entities.isEmpty ? nil : SC.Contour(entities: entities, isClosed: closed)
        }
    }

    private static func near(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Bool {
        simd_distance(a, b) <= joinTolerance
    }

    /// Comes back to where it started, with more than a single line in between.
    private static func isClosed(_ chain: [SIMD2<Double>]) -> Bool {
        chain.count > 2 && near(chain[0], chain[chain.count - 1])
    }
}

extension STEPDocumentScene {

    /// The sampled points of each wanted edge in canvas mm (its body's position applied).
    func edgePoints(for ids: Set<STEP.EdgeID>) -> [STEP.EdgeID: [SIMD3<Float>]] {
        var result: [STEP.EdgeID: [SIMD3<Float>]] = [:]
        for body in content.geometry.bodies {
            let offset = position(of: body.id)
            for edge in body.edges where ids.contains(edge.id) {
                let raw = body.points[edge.vertices]
                guard let first = raw.first else { continue }
                // Consecutive line segments: the start, then the end of every segment.
                var points = [first + offset]
                var index = raw.startIndex
                while index + 1 < raw.endIndex {
                    points.append(raw[index + 1] + offset)
                    index += 2
                }
                result[edge.id] = points
            }
        }
        return result
    }
}

extension STEPWorkspace {

    private func importIDs(in targets: [STEPEdgeTarget]) -> [UUID] {
        var seen = Set<UUID>()
        return targets.map(\.importID).filter { seen.insert($0).inserted }
    }

    /// The contours of the edges, for the toolpath engine. Throws when a model or an edge
    /// is gone (the source was removed, or replaced by a different file).
    /// - Parameter frame: the setup the toolpath is cut in. The edges are mapped into it first,
    ///   so the contours are what the machine sees when the stock is turned that way.
    /// - Parameter sharpEdgeOfChamfer: the edges are a chamfer's two rails (at two heights): the
    ///   engine chamfers a sharp edge, which seen from above is where the chamfer meets its wall,
    ///   the lower rail. With edges at one height (a sharp edge picked as it is) nothing changes.
    func contours(for targets: [STEPEdgeTarget], frame: SetupFrame = .identity,
                  sharpEdgeOfChamfer: Bool = false) throws -> [SC.Contour] {
        var polylines = try polylines(for: targets, frame: frame)
        if sharpEdgeOfChamfer, let rails = Self.chamferRails(of: polylines) {
            polylines = rails.lower
        }
        return STEPContourBuilder.contours(from: polylines)
    }

    /// The sampled edges as polylines in the toolpath's frame.
    private func polylines(for targets: [STEPEdgeTarget], frame: SetupFrame) throws -> [[SIMD3<Double>]] {
        var polylines: [[SIMD3<Double>]] = []
        for importID in importIDs(in: targets) {
            guard let scene = documents[importID] else {
                throw ToolpathGenerator.GenerationError.objectNotFound
            }
            let group = targets.filter { $0.importID == importID }
            let points = scene.edgePoints(for: Set(group.map(\.edgeID)))
            for target in group {
                guard let edge = points[target.edgeID] else {
                    throw ToolpathGenerator.GenerationError.shapeNotFound
                }
                polylines.append(edge.map { frame.map(SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z))) })
            }
        }
        return polylines
    }

    /// Edges at two heights split into the upper and the lower: a chamfer's rails. `nil` when
    /// they are all at one height (within 0.02 mm).
    private static func chamferRails(of polylines: [[SIMD3<Double>]])
        -> (upper: [[SIMD3<Double>]], lower: [[SIMD3<Double>]])? {
        let heights = polylines.map { $0.isEmpty ? 0 : $0.reduce(0.0) { $0 + $1.z } / Double($0.count) }
        guard let low = heights.min(), let high = heights.max(), high - low > 0.02 else { return nil }
        let middle = (low + high) / 2
        var upper: [[SIMD3<Double>]] = [], lower: [[SIMD3<Double>]] = []
        for (polyline, height) in zip(polylines, heights) where !polyline.isEmpty {
            if height < middle { lower.append(polyline) } else { upper.append(polyline) }
        }
        return (upper, lower)
    }

    /// What picking a chamfer through its rails says about the chamfer, to start the toolpath's
    /// settings from: the width (how far the face runs sideways), the depth (how far it drops),
    /// and, when the sharp edge is a closed outline, which side of it the chamfer is on:
    /// `.inside` when the upper rail is inside the lower one (the edge of a part or a boss),
    /// `.outside` when it is outside (the rim of a hole). `nil` when the edges are not two rails.
    func chamferSuggestion(for targets: [STEPEdgeTarget], frame: SetupFrame = .identity)
        -> (width: Double, depth: Double, side: SC.CutSide?)? {
        guard let all = try? polylines(for: targets, frame: frame),
              let rails = Self.chamferRails(of: all), !rails.upper.isEmpty, !rails.lower.isEmpty else { return nil }

        func flat(_ p: SIMD3<Double>) -> SIMD2<Double> { SIMD2<Double>(p.x, p.y) }
        func height(_ polylines: [[SIMD3<Double>]]) -> Double {
            let points = polylines.flatMap { $0 }
            return points.reduce(0.0) { $0 + $1.z } / Double(max(points.count, 1))
        }
        let depth = height(rails.upper) - height(rails.lower)

        // Segments of the lower rail, seen from above.
        var segments: [(SIMD2<Double>, SIMD2<Double>)] = []
        for polyline in rails.lower {
            for index in 0..<max(polyline.count - 1, 0) { segments.append((flat(polyline[index]), flat(polyline[index + 1]))) }
        }
        guard !segments.isEmpty else { return nil }

        func distance(_ p: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            let ab = b - a
            let length = simd_length_squared(ab)
            let t = length > 1e-12 ? min(1, max(0, simd_dot(p - a, ab) / length)) : 0
            return simd_distance(p, a + ab * t)
        }
        // The upper rail's starting points, each against the lower rail.
        let samples = rails.upper.compactMap { $0.first }.map(flat)
        let widths = samples.map { p in segments.map { distance(p, $0.0, $0.1) }.min() ?? 0 }.sorted()
        guard let width = widths.isEmpty ? nil : widths[widths.count / 2], width > 0.001 else { return nil }

        // Inside or outside needs a closed lower rail: every point where edges meet is shared by two.
        var degree: [SIMD2<Int>: Int] = [:]
        func cell(_ p: SIMD2<Double>) -> SIMD2<Int> {
            SIMD2<Int>(Int((p.x / 0.01).rounded()), Int((p.y / 0.01).rounded()))
        }
        for polyline in rails.lower {
            guard let first = polyline.first, let last = polyline.last else { continue }
            let (a, b) = (cell(flat(first)), cell(flat(last)))
            if a != b {
                degree[a, default: 0] += 1
                degree[b, default: 0] += 1
            }
        }
        var side: SC.CutSide?
        if !degree.values.contains(where: { $0 % 2 != 0 }), let point = samples.first {
            // Crossings of a ray to the right: odd means inside.
            var inside = false
            for (a, b) in segments where (a.y > point.y) != (b.y > point.y) {
                if point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            }
            side = inside ? .inside : .outside
        }
        return ((width * 1000).rounded() / 1000, (depth * 1000).rounded() / 1000, side)
    }

    /// End Z for a toolpath cutting these edges: the distance from z0 down to the edges,
    /// the shortest one when they are at different heights. An edge's height is the mean Z
    /// of its points; edges at or above z0 have no depth to cut and are ignored. The circle
    /// at the top of a hole counts as the circle at its bottom, so a hole is cut to its depth.
    /// `nil` when none of them is below z0.
    /// - Parameter frame: the setup the toolpath is cut in: depth is measured from that setup's z0.
    func suggestedEndZ(for targets: [STEPEdgeTarget], frame: SetupFrame = .identity) -> Double? {
        var depths: [Double] = []
        for importID in importIDs(in: targets) {
            guard let scene = documents[importID] else { continue }
            let ids = Set(targets.filter { $0.importID == importID }.map(\.edgeID))
            let bottoms = scene.content.geometry.holeBottoms(of: ids)
            let cut = Set(ids.map { bottoms[$0] ?? $0 })
            for points in scene.edgePoints(for: cut).values where !points.isEmpty {
                let meanZ = points.reduce(0.0) { sum, point in
                    sum + frame.map(SIMD3<Double>(Double(point.x), Double(point.y), Double(point.z))).z
                } / Double(points.count)
                if -meanZ > 0.001 { depths.append(-meanZ) }
            }
        }
        guard let shortest = depths.min() else { return nil }
        return -((shortest * 1000).rounded() / 1000)
    }
}
