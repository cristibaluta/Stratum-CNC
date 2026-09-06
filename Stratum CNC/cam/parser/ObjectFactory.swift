//
//  ObjectFactory.swift
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

        guard let combinedBounds = paths.combinedBounds else {
            return nil
        }

        let originalSize = CGSize(width: max(combinedBounds.width, 0.001),
                                  height: max(combinedBounds.height, 0.001))

        let normalizedPaths = paths.map {
            $0.normalize(relativeTo: combinedBounds)
        }

        return D2_Object(
            name: name,
            paths: normalizedPaths,
            position: CGPoint(x: combinedBounds.minX, y: combinedBounds.minY),
            originalSize: originalSize,
            width: originalSize.width
        )
    }
}
