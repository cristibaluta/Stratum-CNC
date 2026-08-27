//
//  SVGObjectFactory.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import Foundation

struct CAM_ObjectFactory {

    func makeObject(name: String, paths: [STBezierPath]) -> CAM_Object? {

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

        return CAM_Object(
            name: name,
            paths: normalizedPaths,
            position: CGPoint(x: bounds.minX, y: bounds.minY),
            originalSize: originalSize,
            width: originalSize.width
        )
    }

    private func combinedBounds(of paths: [STBezierPath]) -> CGRect? {

        paths.reduce(into: Optional<CGRect>.none) { result, path in
            result = result?.union(path.bounds) ?? path.bounds
        }
    }

    private func normalizedPath(_ source: STBezierPath, relativeTo bounds: CGRect) -> STBezierPath {

        guard let path = source.copy() as? STBezierPath else {
            return source
        }

        path.transform(using: AffineTransform(translationByX: -bounds.minX, byY: -bounds.minY))

        return path
    }
}
