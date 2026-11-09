//
//  STEPSelectionFeature.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.11.2026.
//


//
//  STEPDisplayGeometry+Feature.swift
//  Stratum CNC
//
//  What a selection of STEP edges is (circles, a closed outline, a line, an open path) and
//  which operations make sense for it. "Add toolpath" on the canvas offers exactly those.
//

import Foundation
import simd
import SwiftSTEP

/// The kind of feature a selection of edges forms.
enum STEPSelectionFeature: Equatable, Sendable {
    /// Only full circles: the rims of holes or studs.
    case holes
    /// Edges that join into closed outlines (a face's contour, a pocket, a boss).
    /// `horizontal`: they lie in a plane facing up or down.
    case closedProfile(horizontal: Bool)
    /// One straight edge.
    case line
    /// Anything else: open chains of edges, arcs, curves.
    case openPath
}

extension STEPDisplayGeometry {

    /// What `ids` form, given their measures and the plane they lie in (both already worked
    /// out by the scene for the selection). `nil` for an empty selection.
    func feature(of ids: Set<STEP.EdgeID>, measures: [EdgeMeasure], plane: Plane?) -> STEPSelectionFeature? {
        guard !ids.isEmpty, !measures.isEmpty else { return nil }
        if measures.allSatisfy({ $0.kind == .circle }) {
            return .holes
        }
        if isClosed(ids) {
            let horizontal = plane.map { abs($0.normal.z) > 0.9999 } ?? false
            return .closedProfile(horizontal: horizontal)
        }
        if measures.count == 1, measures[0].kind == .line {
            return .line
        }
        return .openPath
    }

    /// The edges join into closed outlines: every point where edges meet has an even number of
    /// them (a circle closes on itself). Checked per body.
    func isClosed(_ ids: Set<STEP.EdgeID>) -> Bool {
        struct Key: Hashable { let x: Int32, y: Int32, z: Int32 }
        func key(_ p: SIMD3<Float>) -> Key {
            let q = Self.measureTolerance
            return Key(x: Int32((p.x / q).rounded()), y: Int32((p.y / q).rounded()), z: Int32((p.z / q).rounded()))
        }

        var any = false
        for body in bodies {
            var degree: [Key: Int] = [:]
            for edge in body.edges where ids.contains(edge.id) {
                any = true
                let a = key(body.points[edge.vertices.lowerBound])
                let b = key(body.points[edge.vertices.upperBound - 1])
                if a != b {
                    degree[a, default: 0] += 1
                    degree[b, default: 0] += 1
                }
            }
            if degree.values.contains(where: { $0 % 2 != 0 }) { return false }
        }
        return any
    }
}

extension OperationKind {

    /// The operations offered for a selection of STEP edges, most likely first.
    static func operations(for feature: STEPSelectionFeature) -> [OperationKind] {
        switch feature {
            case .holes:
                return [.drilling, .threadMilling, .counterbore, .boring, .pocket, .contour, .chamfer]
            case .closedProfile(let horizontal):
                return horizontal
                    ? [.pocket, .contour, .facing, .chamfer, .engrave]
                    : [.pocket, .contour, .chamfer, .engrave]
            case .line:
                return [.contour, .slotting, .engrave, .chamfer]
            case .openPath:
                return [.contour, .engrave, .chamfer]
        }
    }
}