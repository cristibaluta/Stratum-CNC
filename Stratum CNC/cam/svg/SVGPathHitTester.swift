//
//  SVGPathHitTester.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit

struct SVGCanvasHitTester {

    let tolerance: CGFloat

    func hitTest(worldPoint: CGPoint,
                 objects: [SVGObject],
                 nodes: [UUID: SVGObjectNode],
                 worldLayer: CALayer,
                 zoomScale: CGFloat) -> SVGPathSelection? {

        for object in objects.reversed() {

            guard let node = nodes[object.id] else {
                continue
            }

            let localPoint = node.layer.convert(worldPoint, from: worldLayer)
            let localTolerance = tolerance / max(zoomScale * object.scale, 0.000001)

            for index in object.paths.indices.reversed() {

                let path = object.paths[index]
                let hitBounds = path.bounds.insetBy(dx: -localTolerance, dy: -localTolerance)

                guard hitBounds.contains(localPoint) else {
                    continue
                }

                let strokedPath =
                    path.cgPath.copy(
                        strokingWithWidth: max(localTolerance * 2, 0.5),
                        lineCap: .round,
                        lineJoin: .round,
                        miterLimit: 10
                    )

                if strokedPath.contains(localPoint) {
                    return SVGPathSelection(objectID: object.id, pathIndex: index)
                }
            }
        }

        return nil
    }
}
