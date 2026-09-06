//
//  SVGImporter.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 06/09/2026.
//

import Foundation
import PocketSVG
import SwiftDXF

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
                let p = path
                let nsTransform = AffineTransform(
                    m11: cg.a,
                    m12: cg.b,
                    m21: cg.c,
                    m22: cg.d,
                    tX: cg.tx,
                    tY: cg.ty
                )
                p.transform(using: nsTransform)
                bezierPaths.append(p)
            } else {
                bezierPaths.append(path)
            }
        }

        #if os(macOS)
        // SVG coordinate system starts from top-left
        // Mac coordinate system starts from bottom-left
        // We need to flip all the y values of the bezierPaths while maintaining the viewbox
        let flippedPaths = bezierPaths.map { $0.pathWithFlippedY(inHeight: svg.viewBox.height) }
        bezierPaths = flippedPaths
        #endif

        if let object = factory.makeObject(name: url.lastPathComponent, paths: bezierPaths) {
            return object
        }
        return nil
    }
}

extension STBezierPath {

    func dxfEntities(
        tolerance: Double = 0.01,
        layer: String = "0",
        color: Int = 0
    ) -> [SwiftDXF.DXF.Entity] {

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
}

private struct DXFPathConverter {

    private(set) var entities: [SwiftDXF.DXF.Entity] = []

    private let tolerance: Double
    private let layer: String
    private let color: Int

    private var currentPoint: CGPoint?
    private var subpathStartPoint: CGPoint?

    init(
        tolerance: Double,
        layer: String,
        color: Int
    ) {
        self.tolerance = max(tolerance, 0.000001)
        self.layer = layer
        self.color = color
    }

    mutating func consume(_ element: CGPathElement) {
        switch element.type {

        case .moveToPoint:
            let point = element.points[0]

            currentPoint = point
            subpathStartPoint = point

        case .addLineToPoint:
            guard let start = currentPoint else {
                return
            }

            let end = element.points[0]

            appendLine(
                from: start,
                to: end
            )

            currentPoint = end

        case .addQuadCurveToPoint:
            guard let start = currentPoint else {
                return
            }

            let control = element.points[0]
            let end = element.points[1]

            appendFlattenedQuadratic(
                from: start,
                control: control,
                to: end
            )

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

            currentPoint = start

        @unknown default:
            break
        }
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
        let steps = bezierStepCount(
            from: p0,
            control1: p1,
            control2: p1,
            to: p2,
            tolerance: tolerance
        )

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

private func bezierStepCount(
    from p0: CGPoint,
    control1 p1: CGPoint,
    control2 p2: CGPoint,
    to p3: CGPoint,
    tolerance: Double
) -> Int {
    let length =
        distance(p0, p1)
        + distance(p1, p2)
        + distance(p2, p3)

    return max(
        8,
        Int(ceil(length / max(tolerance, 0.0001)))
    )
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
