//
//  DXF+Transform.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//
//  Everything here exists to keep `D2_Object.entities` honest: it must
//  always describe the same local (origin-at-0,0, unrotated, 1:1 scale)
//  frame that `D2_Object.paths` describes, and only ever get mapped into
//  world/machine space on demand — never baked in and stored.
//
//  `translated` (via `Array.normalized(relativeTo:)`) is used once, at
//  import time, to shift raw file coordinates into that local frame —
//  the DXF.Entity equivalent of `STBezierPath.normalize(relativeTo:)`.
//
//  `resolved` is used every time (typically at g-code export) something
//  needs the *current* world-space geometry — it applies the exact same
//  translate/scale/rotate math `D2_ObjectNode` uses to place the CALayer
//  on screen, so what's drawn and what gets machined can never disagree.

import Foundation
import SwiftDXF

extension DXF.Point {
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

extension CGPoint {
    var dxfPoint: DXF.Point {
        DXF.Point(Double(x), Double(y))
    }
}

extension Array where Element == DXF.Entity {

    /// Shifts every entity so `bounds.origin` becomes local (0, 0) — the
    /// same convention `STBezierPath.normalize(relativeTo:)` uses for
    /// `paths`. Call this once at import time so `entities` and `paths`
    /// describe the same local frame.
    func normalized(relativeTo bounds: CGRect) -> [DXF.Entity] {
        map { $0.translated(dx: -bounds.minX, dy: -bounds.minY) }
    }
}

extension DXF.Entity {

    /// Pure origin shift, no scale or rotation. Used only for the one-time
    /// import normalization above.
    func translated(dx: CGFloat, dy: CGFloat) -> DXF.Entity {
        resolved(
            worldPoint: { CGPoint(x: $0.x + dx, y: $0.y + dy) },
            worldVector: { $0 }, // a direction is translation-invariant
            scale: 1,
            rotationDegrees: 0
        )
    }

    /// Returns this entity mapped from local space into world/machine space.
    ///
    /// - Parameters:
    ///   - worldPoint: maps a local *point* into world space (translate + rotate + scale).
    ///   - worldVector: maps a local *direction* into world space (rotate + scale only — e.g.
    ///     an ellipse's `majorAxis`, which is relative to its center and must not be translated).
    ///   - scale: applied to radii/heights, which have no direction to rotate.
    ///   - rotationDegrees: added to absolute angle fields (arc sweep, text rotation).
    func resolved(worldPoint: (CGPoint) -> CGPoint,
                  worldVector: (CGPoint) -> CGPoint,
                  scale: CGFloat,
                  rotationDegrees: CGFloat) -> DXF.Entity {
        switch self {

        case let .line(a, b, layer, color):
            return .line(a: worldPoint(a.cgPoint).dxfPoint,
                         b: worldPoint(b.cgPoint).dxfPoint,
                         layer: layer, color: color)

        case let .circle(center, radius, layer, color):
            return .circle(center: worldPoint(center.cgPoint).dxfPoint,
                           radius: radius * Double(scale),
                           layer: layer, color: color)

        case let .arc(center, radius, startDeg, endDeg, layer, color):
            return .arc(center: worldPoint(center.cgPoint).dxfPoint,
                        radius: radius * Double(scale),
                        startDeg: startDeg + Double(rotationDegrees),
                        endDeg: endDeg + Double(rotationDegrees),
                        layer: layer, color: color)

        case let .ellipse(center, majorAxis, ratio, startParam, endParam, layer, color):
            return .ellipse(center: worldPoint(center.cgPoint).dxfPoint,
                            majorAxis: worldVector(majorAxis.cgPoint).dxfPoint,
                            ratio: ratio,
                            startParam: startParam,
                            endParam: endParam,
                            layer: layer, color: color)

        case let .point(at, layer, color):
            return .point(at: worldPoint(at.cgPoint).dxfPoint, layer: layer, color: color)

        case let .text(at, height, rotationDeg, string, layer, color):
            return .text(at: worldPoint(at.cgPoint).dxfPoint,
                         height: height * Double(scale),
                         rotationDeg: rotationDeg + Double(rotationDegrees),
                         string: string, layer: layer, color: color)

        case let .polyline(vertices, closed, layer, color):
            let transformed = vertices.map {
                DXF.PolyVertex(worldPoint($0.point.cgPoint).dxfPoint, bulge: $0.bulge)
            }
            return .polyline(vertices: transformed, closed: closed, layer: layer, color: color)

        case .dimension:
            // SwiftDXF models DIMENSION as a semantic measurement, not drawable
            // points, and D2_Object doesn't consume it yet (see DXFImporter's
            // bezierPath()). Passed through unchanged; revisit if dimensions
            // ever need to move with the object.
            return self
        }
    }
}
