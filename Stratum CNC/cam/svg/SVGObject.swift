//
//  SVGObject.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit

final class SVGObject {

    let id: UUID
    var name: String

    /// Paths normalized so their origin is at (0, 0).
    let paths: [NSBezierPath]

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
        paths: [NSBezierPath],
        position: CGPoint,
        originalSize: CGSize,
        width: CGFloat
    ) {
        self.id = id
        self.name = name
        self.paths = paths
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
}
