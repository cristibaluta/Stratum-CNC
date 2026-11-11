//
//  CGPoint+Math.swift
//  Stratum CNC
//

import Foundation
import CoreGraphics

extension CGPoint {

    func lerp(to other: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * t,
                y: y + (other.y - y) * t)
    }

    func midpoint(to other: CGPoint) -> CGPoint {
        lerp(to: other, t: 0.5)
    }

    /// Angle in radians of the vector from `self` to `other`.
    func angle(to other: CGPoint) -> CGFloat {
        atan2(other.y - y, other.x - x)
    }

    func offsetBy(dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}

extension CGPoint {

    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
