//
//  STBezierPath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
typealias STBezierPath = NSBezierPath
#else
import UIKit
typealias STBezierPath = UIBezierPath

/// `UIBezierPath` under the names `NSBezierPath` uses, so the importers build
/// paths the same way on both platforms.
extension UIBezierPath {

    func line(to point: CGPoint) {
        addLine(to: point)
    }

    func curve(to point: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {
        addCurve(to: point, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
    }

    /// AppKit's convention: angles in degrees, counter-clockwise (y up) unless
    /// `clockwise`. UIKit takes radians, and its `clockwise: true` is the
    /// direction of increasing angle, so the flag flips.
    func appendArc(withCenter center: CGPoint, radius: CGFloat,
                   startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        addArc(withCenter: center, radius: radius,
               startAngle: startAngle * .pi / 180, endAngle: endAngle * .pi / 180,
               clockwise: !clockwise)
    }
}
#endif

/// One element of a path, with quadratic curves already promoted to cubic.
enum STPathElement {
    case move(CGPoint)
    case line(CGPoint)
    case curve(CGPoint, CGPoint, CGPoint)   // control 1, control 2, end
    case close
}

extension STBezierPath {

    /// The path's elements, read through `cgPath` so both platforms agree.
    var stElements: [STPathElement] {
        var elements: [STPathElement] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        cgPath.applyWithBlock { pointer in
            let element = pointer.pointee
            let p = element.points
            switch element.type {
            case .moveToPoint:
                current = p[0]
                start = p[0]
                elements.append(.move(p[0]))
            case .addLineToPoint:
                current = p[0]
                elements.append(.line(p[0]))
            case .addQuadCurveToPoint:
                // Promote to cubic
                let control = p[0]
                let end = p[1]
                let c1 = CGPoint(x: current.x + 2.0 / 3.0 * (control.x - current.x),
                                 y: current.y + 2.0 / 3.0 * (control.y - current.y))
                let c2 = CGPoint(x: end.x + 2.0 / 3.0 * (control.x - end.x),
                                 y: end.y + 2.0 / 3.0 * (control.y - end.y))
                current = end
                elements.append(.curve(c1, c2, end))
            case .addCurveToPoint:
                current = p[2]
                elements.append(.curve(p[0], p[1], p[2]))
            case .closeSubpath:
                current = start
                elements.append(.close)
            @unknown default:
                break
            }
        }
        return elements
    }

    /// Transforms the path in place (`transform(using:)` on AppKit, `apply` on UIKit).
    func applyTransform(_ transform: CGAffineTransform) {
        #if os(macOS)
        self.transform(using: AffineTransform(m11: transform.a, m12: transform.b,
                                              m21: transform.c, m22: transform.d,
                                              tX: transform.tx, tY: transform.ty))
        #else
        apply(transform)
        #endif
    }

    func pathWithFlippedY(inHeight height: CGFloat) -> STBezierPath {
        let newPath = STBezierPath()
        func flip(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x, y: height - p.y)
        }

        for element in stElements {
            switch element {
            case .move(let p):
                newPath.move(to: flip(p))
            case .line(let p):
                newPath.line(to: flip(p))
            case .curve(let c1, let c2, let end):
                newPath.curve(to: flip(end), controlPoint1: flip(c1), controlPoint2: flip(c2))
            case .close:
                newPath.close()
            }
        }
        return newPath
    }

    func normalize(relativeTo bounds: CGRect) -> STBezierPath {

        guard let path = self.copy() as? STBezierPath else {
            return self
        }

        path.applyTransform(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))

        return path
    }

    /// Splits the path into one path per subpath (every `moveTo` starts a new
    /// one). An SVG `<path>` often holds several — e.g. a cat silhouette plus
    /// its eye, nose and ear cut-outs — and this lets each be selected and
    /// machined on its own.
    ///
    /// Curves and closes are copied as-is, so the pieces together draw exactly
    /// what the original did. A lone `moveTo` (nothing drawn) is dropped.
    func subpaths() -> [STBezierPath] {
        var result: [STBezierPath] = []
        var current: STBezierPath?
        var currentElementCount = 0
        // Where the current subpath began. After a `close`, an element that has
        // no `moveTo` of its own (legal in SVG: "Z L …") continues from here.
        var start = CGPoint.zero

        func flush() {
            if let path = current, currentElementCount > 1 {
                result.append(path)
            }
            current = nil
            currentElementCount = 0
        }

        func ensureCurrent() -> STBezierPath {
            if let path = current {
                return path
            }
            let path = STBezierPath()
            path.move(to: start)
            currentElementCount = 1
            current = path
            return path
        }

        for element in stElements {
            switch element {
            case .move(let p):
                flush()
                start = p
                let path = STBezierPath()
                path.move(to: start)
                current = path
                currentElementCount = 1
            case .line(let p):
                ensureCurrent().line(to: p)
                currentElementCount += 1
            case .curve(let c1, let c2, let end):
                ensureCurrent().curve(to: end, controlPoint1: c1, controlPoint2: c2)
                currentElementCount += 1
            case .close:
                if let path = current {
                    path.close()
                    currentElementCount += 1
                    flush()
                }
            }
        }
        flush()

        return result
    }
}

extension Array<STBezierPath> {
    var combinedBounds: CGRect? {
        self.reduce(into: Optional<CGRect>.none) { result, path in
            result = result?.union(path.bounds) ?? path.bounds
        }
    }
}
