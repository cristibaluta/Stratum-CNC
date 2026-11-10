//
//  FloatingPoint+Angle.swift
//  Stratum CNC
//

import Foundation

extension FloatingPoint {

    /// Degrees → radians.
    var inRadians: Self { self * .pi / 180 }

    /// Radians → degrees.
    var inDegrees: Self { self * 180 / .pi }
}
