//
//  ObjectFactory.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import Foundation
import SwiftDXF
import StratumCAM

struct ObjectFactory {

    /// - Parameter contours: index-aligned with `paths` (see `D2_Object.contours`).
    func makeObject(name: String, paths: [STBezierPath], entities: [DXF.Entity], contours: [[SC.Contour]]) -> D2_Object? {

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
        let normalizedContours = contours.map { group in
            group.map { $0.translated(dx: -combinedBounds.minX, dy: -combinedBounds.minY) }
        }

        return D2_Object(
            name: name,
            paths: normalizedPaths,
            entities: normalizedEntities,
            contours: normalizedContours,
            position: CGPoint(x: combinedBounds.minX, y: combinedBounds.minY),
            originalSize: originalSize,
            width: originalSize.width
        )
    }
}
