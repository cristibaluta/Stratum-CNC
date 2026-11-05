//
//  STEPEdgeTarget.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 02.11.2026.
//


import Foundation
import simd
import StratumCAM

/// A STEP edge a toolpath cuts. Same identity as the viewer's `STEPEdgeID`, in a form
/// that is saved with the toolpath. Stable as long as the source file is unchanged.
struct STEPEdgeTarget: Codable, Hashable, Sendable {
    let importID: UUID
    let representationID: Int
    let bodyEntityID: Int
    let edgeEntityID: Int

    init(_ id: STEPEdgeID) {
        importID = id.importID
        representationID = id.bodyID.representationID
        bodyEntityID = id.bodyID.entityID
        edgeEntityID = id.entityID
    }

    var edgeID: STEPEdgeID {
        STEPEdgeID(importID: importID,
                   bodyID: STEPBodyID(representationID: representationID, entityID: bodyEntityID),
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

    /// The sampled points of each wanted edge in canvas mm (the model's position applied).
    func edgePoints(for ids: Set<STEPEdgeID>) -> [STEPEdgeID: [SIMD3<Float>]] {
        var result: [STEPEdgeID: [SIMD3<Float>]] = [:]
        for body in content.geometry.bodies {
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
    func contours(for targets: [STEPEdgeTarget], frame: SetupFrame = .identity) throws -> [SC.Contour] {
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
        return STEPContourBuilder.contours(from: polylines)
    }

    /// End Z for a toolpath cutting these edges: the distance from z0 down to the edges,
    /// the shortest one when they are at different heights. An edge's height is the mean Z
    /// of its points; edges at or above z0 have no depth to cut and are ignored.
    /// `nil` when none of them is below z0.
    /// - Parameter frame: the setup the toolpath is cut in: depth is measured from that setup's z0.
    func suggestedEndZ(for targets: [STEPEdgeTarget], frame: SetupFrame = .identity) -> Double? {
        var depths: [Double] = []
        for importID in importIDs(in: targets) {
            guard let scene = documents[importID] else { continue }
            let ids = Set(targets.filter { $0.importID == importID }.map(\.edgeID))
            for points in scene.edgePoints(for: ids).values where !points.isEmpty {
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