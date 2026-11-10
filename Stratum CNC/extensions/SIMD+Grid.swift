//
//  SIMD+Grid.swift
//  Stratum CNC
//

import Foundation
import simd

extension SIMD2 where Scalar == Double {

    /// Integer grid cell containing the point. `quantum` is the cell edge length,
    /// so points closer than ~`quantum` collapse to the same hashable key.
    func cell(quantum: Double = 0.01) -> SIMD2<Int> {
        SIMD2<Int>(Int((x / quantum).rounded()), Int((y / quantum).rounded()))
    }
}

extension SIMD3 where Scalar == Double {

    /// Hashable quantized key for vertex welding / dedup.
    func quantized(_ quantum: Double) -> SIMD3<Int32> {
        SIMD3<Int32>(Int32((x / quantum).rounded()),
                     Int32((y / quantum).rounded()),
                     Int32((z / quantum).rounded()))
    }
}
