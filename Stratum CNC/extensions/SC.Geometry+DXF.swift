//
//  SC+DXF.swift
//  StratumCAMDXF
//
//  Optional adapter: converts SwiftDXF entities to the library-native `SC.Geometry`.
//

import Foundation
import StratumCAM
import SwiftDXF

extension SC.Geometry {

    /// Converts a DXF entity. Returns `nil` for entities that can't be machined
    /// (text, dimensions).
    public init?(dxf entity: DXF.Entity) {
        switch entity {
            case let .line(a, b, _, _):
                self = .line(a: SIMD2(a.x, a.y), b: SIMD2(b.x, b.y))

            case let .circle(center, radius, _, _):
                self = .circle(center: SIMD2(center.x, center.y), radius: radius)

            case let .arc(center, radius, startDeg, endDeg, _, _):
                self = .arc(center: SIMD2(center.x, center.y), radius: radius, startDeg: startDeg, endDeg: endDeg)

            case let .ellipse(center, majorAxis, ratio, startParam, endParam, _, _):
                self = .ellipse(center: SIMD2(center.x, center.y),
                                majorAxis: SIMD2(majorAxis.x, majorAxis.y),
                                ratio: ratio,
                                startParam: startParam,
                                endParam: endParam)

            case let .point(at, _, _):
                self = .point(at: SIMD2(at.x, at.y))

            case let .polyline(vertices, closed, _, _):
                self = .polyline(vertices: vertices.map { Vertex(SIMD2($0.point.x, $0.point.y), bulge: $0.bulge) },
                                 closed: closed)

            case .text, .dimension:
                return nil
        }
    }
}

extension Sequence where Element == DXF.Entity {

    /// Machinable geometry from a DXF entity list; text and dimensions are skipped.
    public var scGeometry: [SC.Geometry] {
        compactMap { SC.Geometry(dxf: $0) }
    }
}

extension EntityChainer {

    /// Convenience: chains DXF entities straight into contours.
    public static func chain(_ entities: [DXF.Entity], tolerance: Double = 1e-3) -> [SC.Contour] {
        chain(entities.scGeometry, tolerance: tolerance)
    }
}
