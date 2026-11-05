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
import StratumCAM

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

extension SC.Contour {

    /// Pure origin shift — the contour equivalent of `DXF.Entity.translated`.
    /// Used once at import time to put contours in the same local frame as `paths`.
    func translated(dx: CGFloat, dy: CGFloat) -> SC.Contour {
        mapEntities { $0.translated(dx: dx, dy: dy) }
    }

    /// Maps the contour from local space into world/machine space; see
    /// `DXF.Entity.resolved` for what each parameter means.
    func resolved(worldPoint: (CGPoint) -> CGPoint,
                  worldVector: (CGPoint) -> CGPoint,
                  scale: CGFloat,
                  rotationDegrees: CGFloat) -> SC.Contour {
        mapEntities {
            $0.resolved(worldPoint: worldPoint,
                        worldVector: worldVector,
                        scale: scale,
                        rotationDegrees: rotationDegrees)
        }
    }

    /// The mirror image across the line `y = mirrorLine` (`.x` axis: the part is flipped about X)
    /// or `x = mirrorLine` (`.y` axis). Used to lay a 2D shape on the face that is up when the
    /// stock is flipped over. A mirror reverses every curve's sense of rotation, so arcs and
    /// ellipses keep their counter-clockwise form by swapping their ends, and the chain is
    /// walked the other way round to compensate (`reversed` toggles).
    func mirrored(about axis: SetupAxis, at mirrorLine: Double) -> SC.Contour {
        SC.Contour(entities: entities.map { chained in
                       let (geometry, flipsSense) = chained.geometry.mirrored(about: axis, at: mirrorLine)
                       return SC.Contour.Chained(geometry: geometry,
                                                 reversed: flipsSense ? !chained.reversed : chained.reversed)
                   },
                   isClosed: isClosed,
                   islands: islands.map { $0.mirrored(about: axis, at: mirrorLine) })
    }

    // `reversed` (the chaining direction) and `isClosed` are properties of the
    // chain, not of the geometry, so they survive any point transform unchanged.
    private func mapEntities(_ transform: (SC.Geometry) -> SC.Geometry) -> SC.Contour {
        SC.Contour(entities: entities.map { SC.Contour.Chained(geometry: transform($0.geometry), reversed: $0.reversed) },
                   isClosed: isClosed,
                   islands: islands.map { $0.mapEntities(transform) })
    }
}

extension SIMD2 where Scalar == Double {
    var cg: CGPoint {
        CGPoint(x: x, y: y)
    }
}

extension CGPoint {
    var simd: SIMD2<Double> {
        SIMD2(Double(x), Double(y))
    }
}

extension SC.Geometry {

    /// Pure origin shift, no scale or rotation.
    func translated(dx: CGFloat, dy: CGFloat) -> SC.Geometry {
        resolved(
            worldPoint: { CGPoint(x: $0.x + dx, y: $0.y + dy) },
            worldVector: { $0 },
            scale: 1,
            rotationDegrees: 0
        )
    }

    /// Geometry counterpart of `DXF.Entity.resolved`.
    func resolved(worldPoint: (CGPoint) -> CGPoint,
                  worldVector: (CGPoint) -> CGPoint,
                  scale: CGFloat,
                  rotationDegrees: CGFloat) -> SC.Geometry {
        switch self {
        case let .line(a, b):
            return .line(a: worldPoint(a.cg).simd, b: worldPoint(b.cg).simd)

        case let .circle(center, radius):
            return .circle(center: worldPoint(center.cg).simd, radius: radius * Double(scale))

        case let .arc(center, radius, startDeg, endDeg):
            return .arc(center: worldPoint(center.cg).simd,
                        radius: radius * Double(scale),
                        startDeg: startDeg + Double(rotationDegrees),
                        endDeg: endDeg + Double(rotationDegrees))

        case let .ellipse(center, majorAxis, ratio, startParam, endParam):
            return .ellipse(center: worldPoint(center.cg).simd,
                            majorAxis: worldVector(majorAxis.cg).simd,
                            ratio: ratio,
                            startParam: startParam,
                            endParam: endParam)

        case let .point(at):
            return .point(at: worldPoint(at.cg).simd)

        case let .polyline(vertices, closed):
            return .polyline(vertices: vertices.map { SC.Geometry.Vertex(worldPoint($0.point.cg).simd, bulge: $0.bulge) },
                             closed: closed)
        }
    }
}

extension SC.Geometry {

    /// Mirror image, see `SC.Contour.mirrored`. `flipsSense` is true for the curves whose
    /// start and end were swapped (arcs, ellipses), so the caller reverses their chain direction.
    func mirrored(about axis: SetupAxis, at mirrorLine: Double) -> (SC.Geometry, flipsSense: Bool) {
        func point(_ p: SIMD2<Double>) -> SIMD2<Double> {
            axis == .x ? SIMD2(p.x, 2 * mirrorLine - p.y) : SIMD2(2 * mirrorLine - p.x, p.y)
        }
        func vector(_ v: SIMD2<Double>) -> SIMD2<Double> {
            axis == .x ? SIMD2(v.x, -v.y) : SIMD2(-v.x, v.y)
        }
        // Angle of a direction after the mirror: θ → −θ across a horizontal line, 180° − θ across a vertical one.
        func angle(_ degrees: Double) -> Double {
            axis == .x ? -degrees : 180 - degrees
        }

        switch self {
        case let .line(a, b):
            return (.line(a: point(a), b: point(b)), false)

        case let .circle(center, radius):
            return (.circle(center: point(center), radius: radius), false)

        case let .arc(center, radius, startDeg, endDeg):
            return (.arc(center: point(center), radius: radius,
                         startDeg: angle(endDeg), endDeg: angle(startDeg)), true)

        case let .ellipse(center, majorAxis, ratio, startParam, endParam):
            // The minor axis is the major one turned a quarter counter-clockwise, which a mirror
            // reverses: the parameter runs the other way, whichever line it is mirrored across.
            return (.ellipse(center: point(center), majorAxis: vector(majorAxis), ratio: ratio,
                             startParam: -endParam, endParam: -startParam), true)

        case let .point(at):
            return (.point(at: point(at)), false)

        case let .polyline(vertices, closed):
            return (.polyline(vertices: vertices.map { SC.Geometry.Vertex(point($0.point), bulge: -$0.bulge) },
                              closed: closed), false)
        }
    }
}
