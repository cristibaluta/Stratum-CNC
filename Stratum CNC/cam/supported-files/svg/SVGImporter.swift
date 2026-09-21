//
//  SVGImporter.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 06/09/2026.
//

import Foundation
import PocketSVG
import SwiftDXF
import StratumCAM

class SVGImporter: Importer {

    private let factory = ObjectFactory()

    func parse(url: URL) -> D2_Object? {

        let svg = SVGLayer(contentsOf: url)
        print(svg.viewBox)
        print(svg.paths)
        print(svg.attributeKeys)

        var bezierPaths: [STBezierPath] = []
        let svgPaths: [SVGBezierPath] = svg.paths
        for path in svgPaths {
//            print(path.svgAttributes)
//            print(path.svgAttributes["transform"] as Any)
            // Some svgs (saved by Inkscape) do not have the real values that will match the viewbox
            // But they contain a transform we can use to scale everything down
            if let cg = path.svgAttributes["transform"] as? CGAffineTransform {
                let nsTransform = AffineTransform(
                    m11: cg.a,
                    m12: cg.b,
                    m21: cg.c,
                    m22: cg.d,
                    tX: cg.tx,
                    tY: cg.ty
                )
                path.transform(using: nsTransform)
            }
            bezierPaths.append(path)
        }

        #if os(macOS)
        // SVG coordinate system starts from top-left
        // Mac coordinate system starts from bottom-left
        // We need to flip all the y values of the bezierPaths while maintaining the viewbox
        bezierPaths = bezierPaths.map { $0.pathWithFlippedY(inHeight: svg.viewBox.height) }
        #endif

        // Derive entities from the final, already-flipped paths so `entities`
        // describes the exact same orientation as `paths` — computing them
        // beforehand (from pre-flip geometry) would leave entities mirrored
        // vertically relative to what's actually drawn.
        let entities = bezierPaths.flatMap { $0.dxfEntities() }
        // Index-aligned with `bezierPaths` — see D2_Object.contours
        let contours = bezierPaths.map { $0.dxfContours() }

        return factory.makeObject(name: url.lastPathComponent, paths: bezierPaths, entities: entities, contours: contours)
    }
}

extension STBezierPath {

    func dxfEntities(tolerance: Double = 0.01, layer: String = "0", color: Int = 0) -> [DXF.Entity] {

        var converter = DXFPathConverter(
            tolerance: tolerance,
            layer: layer,
            color: color
        )

        cgPath.applyWithBlock { elementPointer in
            converter.consume(elementPointer.pointee)
        }

        return converter.entities
    }

    /// Same conversion as `dxfEntities`, but keeps the subpaths apart: one
    /// `SC.Contour` per subpath (each `moveTo` starts a new one). A single SVG
    /// path can hold several — e.g. the outer ring and the hole of an "O" —
    /// and the engine treats a contour as one connected chain, so they must
    /// not be merged.
    func dxfContours(tolerance: Double = 0.01, layer: String = "0", color: Int = 0) -> [SC.Contour] {

        var converter = DXFPathConverter(
            tolerance: tolerance,
            layer: layer,
            color: color
        )

        cgPath.applyWithBlock { elementPointer in
            converter.consume(elementPointer.pointee)
        }
        converter.finish()

        return converter.contours
    }
}

private struct DXFPathConverter {

    private(set) var entities: [DXF.Entity] = []
    /// One per subpath, built from slices of `entities`. Only complete after `finish()`.
    private(set) var contours: [SC.Contour] = []

    private var subpathFirstEntity = 0
    private var subpathExplicitlyClosed = false

    private let tolerance: Double
    private let layer: String
    private let color: Int

    private var currentPoint: CGPoint?
    private var subpathStartPoint: CGPoint?

    init(tolerance: Double, layer: String, color: Int) {
        self.tolerance = max(tolerance, 0.000001)
        self.layer = layer
        self.color = color
    }

    mutating func consume(_ element: CGPathElement) {
        switch element.type {

        case .moveToPoint:
            let point = element.points[0]

            finishSubpath()
            currentPoint = point
            subpathStartPoint = point

        case .addLineToPoint:
            guard let start = currentPoint else {
                return
            }

            let end = element.points[0]
            appendLine(from: start, to: end)
            currentPoint = end

        case .addQuadCurveToPoint:
            guard let start = currentPoint else {
                return
            }

            let control = element.points[0]
            let end = element.points[1]
            appendFlattenedQuadratic(from: start, control: control, to: end)
            currentPoint = end

        case .addCurveToPoint:
            guard let start = currentPoint else {
                return
            }

            let control1 = element.points[0]
            let control2 = element.points[1]
            let end = element.points[2]

            appendFlattenedCubic(
                from: start,
                control1: control1,
                control2: control2,
                to: end
            )

            currentPoint = end

        case .closeSubpath:
            guard
                let current = currentPoint,
                let start = subpathStartPoint
            else {
                return
            }

            if distance(current, start) > 1e-9 {
                appendLine(
                    from: current,
                    to: start
                )
            }

            subpathExplicitlyClosed = true
            currentPoint = start

        @unknown default:
            break
        }
    }

    /// Call once after the last element so the final subpath becomes a contour.
    mutating func finish() {
        finishSubpath()
    }

    /// Turns the entities added since the last subpath boundary into a contour.
    /// Must run *before* `currentPoint`/`subpathStartPoint` are updated by the
    /// next `moveTo`, since it reads them to detect an implicitly closed subpath.
    private mutating func finishSubpath() {
        let chain = entities[subpathFirstEntity...].map {
            SC.Contour.Chained(entity: $0, reversed: false)
        }

        if !chain.isEmpty {
            var isClosed = subpathExplicitlyClosed
            if !isClosed, let current = currentPoint, let start = subpathStartPoint {
                // Ends where it started without an explicit close
                isClosed = distance(current, start) <= 1e-6
            }
            contours.append(SC.Contour(entities: chain, isClosed: isClosed))
        }

        subpathFirstEntity = entities.count
        subpathExplicitlyClosed = false
    }

    private mutating func appendLine(
        from start: CGPoint,
        to end: CGPoint
    ) {
        guard distance(start, end) > 1e-9 else {
            return
        }

        entities.append(
            .line(
                a: SwiftDXF.DXF.Point(
                    Double(start.x),
                    Double(start.y)
                ),
                b: SwiftDXF.DXF.Point(
                    Double(end.x),
                    Double(end.y)
                ),
                layer: layer,
                color: color
            )
        )
    }
}

private extension DXFPathConverter {

    mutating func appendFlattenedQuadratic(
        from p0: CGPoint,
        control p1: CGPoint,
        to p2: CGPoint,
        tolerance: Double = 0.01
    ) {
        let steps = quadraticStepCount(from: p0, control: p1, to: p2, tolerance: tolerance)

        var previous = p0

        for index in 1...steps {
            let t = Double(index) / Double(steps)

            let point = quadraticPoint(
                p0: p0,
                p1: p1,
                p2: p2,
                t: t
            )

            entities.append(
                .line(
                    a: SwiftDXF.DXF.Point(previous.x, previous.y),
                    b: SwiftDXF.DXF.Point(point.x, point.y),
                    layer: "0",
                    color: 0
                )
            )

            previous = point
        }
    }

    mutating func appendFlattenedCubic(
        from p0: CGPoint,
        control1 p1: CGPoint,
        control2 p2: CGPoint,
        to p3: CGPoint,
        tolerance: Double = 0.01
    ) {
        let steps = bezierStepCount(
            from: p0,
            control1: p1,
            control2: p2,
            to: p3,
            tolerance: tolerance
        )

        var previous = p0

        for index in 1...steps {
            let t = Double(index) / Double(steps)

            let point = cubicPoint(
                p0: p0,
                p1: p1,
                p2: p2,
                p3: p3,
                t: t
            )

            entities.append(
                .line(
                    a: SwiftDXF.DXF.Point(previous.x, previous.y),
                    b: SwiftDXF.DXF.Point(point.x, point.y),
                    layer: "0",
                    color: 0
                )
            )

            previous = point
        }
    }
}

private func quadraticPoint(
    p0: CGPoint,
    p1: CGPoint,
    p2: CGPoint,
    t: Double
) -> CGPoint {
    let u = 1.0 - t

    return CGPoint(
        x: u * u * Double(p0.x)
            + 2.0 * u * t * Double(p1.x)
            + t * t * Double(p2.x),

        y: u * u * Double(p0.y)
            + 2.0 * u * t * Double(p1.y)
            + t * t * Double(p2.y)
    )
}

private func cubicPoint(
    p0: CGPoint,
    p1: CGPoint,
    p2: CGPoint,
    p3: CGPoint,
    t: Double
) -> CGPoint {
    let u = 1.0 - t

    return CGPoint(
        x:
            u * u * u * Double(p0.x)
            + 3.0 * u * u * t * Double(p1.x)
            + 3.0 * u * t * t * Double(p2.x)
            + t * t * t * Double(p3.x),

        y:
            u * u * u * Double(p0.y)
            + 3.0 * u * u * t * Double(p1.y)
            + 3.0 * u * t * t * Double(p2.y)
            + t * t * t * Double(p3.y)
    )
}

/// Number of equal-`t` line segments needed to keep a flattened cubic within `tolerance`
/// (same units as the coordinates, mm here) of the true curve.
///
/// This is the standard bound on the deviation of a uniform subdivision:
/// error <= (1/8) * max|B''| / n^2, with max|B''| <= 6 * max(|p0-2p1+p2|, |p1-2p2+p3|),
/// so n = ceil(sqrt(0.75 * M / tolerance)).
///
/// It used to be `ceil(controlPolygonLength / tolerance)` — one segment per 0.01 mm of curve,
/// regardless of how straight or curved it was — which turned a simple outline into tens of
/// thousands of entities and the toolpath engine's output into millions of waypoints.
private func bezierStepCount(
    from p0: CGPoint,
    control1 p1: CGPoint,
    control2 p2: CGPoint,
    to p3: CGPoint,
    tolerance: Double
) -> Int {
    let d1 = hypot(Double(p0.x - 2 * p1.x + p2.x), Double(p0.y - 2 * p1.y + p2.y))
    let d2 = hypot(Double(p1.x - 2 * p2.x + p3.x), Double(p1.y - 2 * p2.y + p3.y))
    let n = (0.75 * max(d1, d2) / max(tolerance, 0.000001)).squareRoot()

    return max(4, Int(n.rounded(.up)))
}

/// Same idea for a quadratic: max|B''| = 2 * |p0-2p1+p2|, so n = ceil(sqrt(0.25 * M / tolerance)).
private func quadraticStepCount(
    from p0: CGPoint,
    control p1: CGPoint,
    to p2: CGPoint,
    tolerance: Double
) -> Int {
    let d = hypot(Double(p0.x - 2 * p1.x + p2.x), Double(p0.y - 2 * p1.y + p2.y))
    let n = (0.25 * d / max(tolerance, 0.000001)).squareRoot()

    return max(4, Int(n.rounded(.up)))
}

private func distance(
    _ a: CGPoint,
    _ b: CGPoint
) -> Double {
    hypot(
        Double(b.x - a.x),
        Double(b.y - a.y)
    )
}
