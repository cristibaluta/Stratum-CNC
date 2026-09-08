//
//  ObjectFactory.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import Foundation
import SwiftDXF

struct ObjectFactory {

    func makeObject(name: String, paths: [STBezierPath], entities: [DXF.Entity]) -> D2_Object? {

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
        // Keep entities describing the exact same local (0,0)-origin frame
        // as paths — see DXF+Transform.swift. Without this they'd stay in
        // raw import coordinates while paths get normalized, and the two
        // would silently disagree about where the geometry sits.
        let normalizedEntities = entities.normalized(relativeTo: combinedBounds)

        return D2_Object(
            name: name,
            paths: normalizedPaths,
            entities: normalizedEntities,
            position: CGPoint(x: combinedBounds.minX, y: combinedBounds.minY),
            originalSize: originalSize,
            width: originalSize.width
        )
    }
}
