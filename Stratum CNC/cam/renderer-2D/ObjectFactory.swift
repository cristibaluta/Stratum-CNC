//
//  SVGObjectFactory.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import Foundation

struct ObjectFactory {

    func makeObject(name: String, paths: [STBezierPath]) -> D2_Object? {

        guard !paths.isEmpty else {
            return nil
        }

        guard let bounds = paths.combinedBounds else {
            return nil
        }

        let originalSize = CGSize(width: max(bounds.width, 0.001),
                                  height: max(bounds.height, 0.001))

        let normalizedPaths = paths.map {
            normalizedPath($0, relativeTo: bounds)
        }

        return D2_Object(
            name: name,
            paths: normalizedPaths,
            position: CGPoint(x: bounds.minX, y: bounds.minY),
            originalSize: originalSize,
            width: originalSize.width
        )
    }

    private func normalizedPath(_ source: STBezierPath, relativeTo bounds: CGRect) -> STBezierPath {

        guard let path = source.copy() as? STBezierPath else {
            return source
        }

        path.transform(using: AffineTransform(translationByX: -bounds.minX, byY: -bounds.minY))

        return path
    }
}
