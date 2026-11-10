//
//  SIMD+Geometry.swift
//  Stratum CNC
//

import Foundation
import simd

extension SIMD2 where Scalar: FloatingPoint {

    var length: Scalar {
        (x * x + y * y).squareRoot()
    }

    func distance(to other: Self) -> Scalar {
        (self - other).length
    }

    /// Unit vector, or `.zero` for a zero-length vector.
    var normalized: Self {
        let len = length
        return len > 0 ? self / len : .zero
    }

    /// Linear interpolation: `t == 0` is `self`, `t == 1` is `other`.
    func lerp(to other: Self, t: Scalar) -> Self {
        self + (other - self) * t
    }

    func midpoint(to other: Self) -> Self {
        (self + other) / 2
    }

    /// Rotated 90° counter-clockwise.
    var perpendicular: Self { Self(-y, x) }

    var isFinite: Bool {
        x.isFinite && y.isFinite
    }

    /// Lifts to 3D, default `z = 0`.
    func xyz(z: Scalar = 0) -> SIMD3<Scalar> {
        SIMD3<Scalar>(x, y, z)
    }
}

extension SIMD2 where Scalar == Double {

    /// Angle in radians from the +X axis.
    var angle: Double {
        atan2(y, x)
    }

    /// Angle in radians of the vector from `origin` to `self`.
    func angle(from origin: Self) -> Double {
        atan2(y - origin.y, x - origin.x)
    }

    init(radius: Double, angle: Double) {
        self.init(radius * cos(angle), radius * sin(angle))
    }
}

extension SIMD3 where Scalar: FloatingPoint {

    var length: Scalar {
        (x * x + y * y + z * z).squareRoot()
    }

    func distance(to other: Self) -> Scalar {
        (self - other).length
    }

    var normalized: Self {
        let len = length
        return len > 0 ? self / len : .zero
    }

    func lerp(to other: Self, t: Scalar) -> Self {
        self + (other - self) * t
    }

    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }

    /// Drops `z`.
    var xy: SIMD2<Scalar> {
        SIMD2<Scalar>(x, y)
    }
}
