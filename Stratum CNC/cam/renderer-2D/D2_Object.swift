//
//  D2_Object.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import Foundation
import SwiftDXF

final class D2_Object {

    let id: UUID
    var name: String

    /// Paths normalized so their origin is at (0, 0).
    let paths: [STBezierPath]
    let entities: [DXF.Entity]

    /// Original imported dimensions.
    let originalSize: CGSize

    /// Bottom-left corner in world/CNC coordinates.
    var position: CGPoint

    /// Current width in mm.
    var width: CGFloat

    /// Rotation around object's center.
    var rotationDegrees: CGFloat

    init(
        id: UUID = UUID(),
        name: String,
        paths: [STBezierPath],
        entities: [DXF.Entity],
        position: CGPoint,
        originalSize: CGSize,
        width: CGFloat
    ) {
        self.id = id
        self.name = name
        self.paths = paths
        self.entities = entities
        self.position = position
        self.originalSize = originalSize
        self.width = width
        self.rotationDegrees = 0
    }

    // MARK: Geometry

    var aspectRatio: CGFloat {
        originalSize.width / max(originalSize.height, 0.000001)
    }

    var height: CGFloat {
        width / max(aspectRatio, 0.000001)
    }

    var center: CGPoint {
        CGPoint(x: position.x + width / 2, y: position.y + height / 2)
    }

    var scale: CGFloat {
        width / max(originalSize.width, 0.000001)
    }

    var rotatedBounds: CGRect {
        let angle = rotationDegrees * .pi / 180
        let cosAngle = abs(cos(angle))
        let sinAngle = abs(sin(angle))
        let rotatedWidth = width * cosAngle + height * sinAngle
        let rotatedHeight = width * sinAngle + height * cosAngle

        return CGRect(x: center.x - rotatedWidth / 2,
                      y: center.y - rotatedHeight / 2,
                      width: rotatedWidth,
                      height: rotatedHeight)
    }

    // MARK: Editing

    func setHeight(_ value: CGFloat) {
        width = max(value * aspectRatio, 0.001)
    }

    func setRotation(_ degrees: CGFloat) {
        rotationDegrees = normalizedAngle(degrees)
    }

    func rotate(by degrees: CGFloat) {
        setRotation(rotationDegrees + degrees)
    }

    private func normalizedAngle(_ degrees: CGFloat) -> CGFloat {
        var result = degrees.truncatingRemainder(dividingBy: 360)

        if result < 0 {
            result += 360
        }

        return result
    }

    // MARK: G-code / export geometry

    /// `entities` transformed into world/machine space using this object's
    /// *current* position, scale and rotation.
    ///
    /// `entities` itself is stored once, at import time, in the same local
    /// (origin-at-0,0, unrotated, 1:1) frame `paths` uses — it never changes
    /// when the object is moved/resized/rotated. G-code generation should
    /// always read `machineEntities`, computed fresh here, and never
    /// `entities` directly: that guarantees the toolpath always matches
    /// whatever is currently drawn on screen, instead of wherever the object
    /// happened to sit at import time.
    var machineEntities: [DXF.Entity] {
        entities.map {
            $0.resolved(worldPoint: worldPoint(fromLocal:),
                       worldVector: worldVector(fromLocal:),
                       scale: scale,
                       rotationDegrees: rotationDegrees)
        }
    }

    /// Maps a point in this object's local coordinate space into world
    /// space, using the exact same translate/scale/rotate math
    /// `D2_ObjectNode.update` uses to place the CALayer on screen. Keeping
    /// this in sync with that method is what keeps drawing and machining
    /// in agreement.
    func worldPoint(fromLocal local: CGPoint) -> CGPoint {
        let half = CGPoint(x: originalSize.width / 2, y: originalSize.height / 2)
        let centered = CGPoint(x: (local.x - half.x) * scale, y: (local.y - half.y) * scale)
        let angle = rotationDegrees * .pi / 180
        let rotated = CGPoint(x: centered.x * cos(angle) - centered.y * sin(angle),
                              y: centered.x * sin(angle) + centered.y * cos(angle))
        return CGPoint(x: center.x + rotated.x, y: center.y + rotated.y)
    }

    /// Maps a local *direction* (e.g. an ellipse's `majorAxis`, which is
    /// relative to its own center) into world space: rotated and scaled like
    /// `worldPoint`, but never translated.
    func worldVector(fromLocal local: CGPoint) -> CGPoint {
        let scaled = CGPoint(x: local.x * scale, y: local.y * scale)
        let angle = rotationDegrees * .pi / 180
        return CGPoint(x: scaled.x * cos(angle) - scaled.y * sin(angle),
                       y: scaled.x * sin(angle) + scaled.y * cos(angle))
    }
}
