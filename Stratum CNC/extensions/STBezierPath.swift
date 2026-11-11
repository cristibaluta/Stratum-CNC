//
//  STBezierPath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation
#if os(macOS)
import AppKit
typealias STBezierPath = NSBezierPath
#else
import UIKit
typealias STBezierPath = UIBezierPath
#endif

extension STBezierPath {

    func pathWithFlippedY(inHeight height: CGFloat) -> STBezierPath {
        let newPath = STBezierPath()
        var points = [STPoint](repeating: .zero, count: 3)

        for i in 0..<self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                newPath.move(to: NSPoint(x: points[0].x, y: height - points[0].y))
            case .lineTo:
                newPath.line(to: NSPoint(x: points[0].x, y: height - points[0].y))
            case .curveTo:
                newPath.curve(
                    to: NSPoint(x: points[2].x, y: height - points[2].y),
                    controlPoint1: NSPoint(x: points[0].x, y: height - points[0].y),
                    controlPoint2: NSPoint(x: points[1].x, y: height - points[1].y)
                )
            case .closePath:
                newPath.close()
            default:
                break
            }
        }
        return newPath
    }

    func normalize(relativeTo bounds: CGRect) -> STBezierPath {

        guard let path = self.copy() as? STBezierPath else {
            return self
        }

        path.transform(using: AffineTransform(translationByX: -bounds.minX, byY: -bounds.minY))

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
        // Where the current subpath began. After a `close`, an element that has
        // no `moveTo` of its own (legal in SVG: "Z L …") continues from here.
        var start: NSPoint = .zero
        var points = [NSPoint](repeating: .zero, count: 3)

        func flush() {
            if let path = current, path.elementCount > 1 {
                result.append(path)
            }
            current = nil
        }

        func ensureCurrent() -> STBezierPath {
            if let path = current {
                return path
            }
            let path = STBezierPath()
            path.move(to: start)
            current = path
            return path
        }

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                flush()
                start = points[0]
                let path = STBezierPath()
                path.move(to: start)
                current = path
            case .lineTo:
                ensureCurrent().line(to: points[0])
            case .curveTo:
                ensureCurrent().curve(to: points[2], controlPoint1: points[0], controlPoint2: points[1])
            case .closePath:
                if let path = current {
                    path.close()
                    flush()
                }
            default:
                break
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
