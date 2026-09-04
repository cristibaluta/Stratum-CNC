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
        var points = [NSPoint](repeating: .zero, count: 3)

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
}

extension Array<STBezierPath> {
    var combinedBounds: CGRect? {
        self.reduce(into: Optional<CGRect>.none) { result, path in
            result = result?.union(path.bounds) ?? path.bounds
        }
    }
}
