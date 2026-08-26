//
//  SVGObjectFactory.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit

struct SVGObjectFactory {

    func makeObject(name: String, paths: [NSBezierPath]) -> SVGObject? {

        guard !paths.isEmpty else {
            return nil
        }

        guard let bounds = combinedBounds(of: paths) else {
            return nil
        }

        let originalSize = CGSize(width: max(bounds.width, 0.001),
                                  height: max(bounds.height, 0.001))

        let normalizedPaths = paths.map {
            normalizedPath($0, relativeTo: bounds)
        }

        return SVGObject(
            name: name,
            paths: normalizedPaths,
            position: CGPoint(x: bounds.minX, y: bounds.minY),
            originalSize: originalSize,
            width: originalSize.width
        )
    }

    private func combinedBounds(of paths: [NSBezierPath]) -> CGRect? {

        paths.reduce(into: Optional<CGRect>.none) { result, path in
            result = result?.union(path.bounds) ?? path.bounds
        }
    }

    private func normalizedPath(_ source: NSBezierPath, relativeTo bounds: CGRect) -> NSBezierPath {

        guard let path = source.copy() as? NSBezierPath else {
            return source
        }

        path.transform(using: AffineTransform(translationByX: -bounds.minX, byY: -bounds.minY))

        return path
    }
}
