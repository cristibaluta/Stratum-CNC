//
//  Ext.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//


//extension float4x4 {
//
//    init(
//        lookAt eye: SIMD3<Float>,
//        target: SIMD3<Float>,
//        up: SIMD3<Float>
//    ) {
//
//        let z =
//            simd_normalize(eye - target)
//
//        let x =
//            simd_normalize(
//                simd_cross(up, z)
//            )
//
//        let y =
//            simd_cross(z, x)
//
//        self.init(
//            SIMD4<Float>(
//                x.x, y.x, z.x, 0
//            ),
//
//            SIMD4<Float>(
//                x.y, y.y, z.y, 0
//            ),
//
//            SIMD4<Float>(
//                x.z, y.z, z.z, 0
//            ),
//
//            SIMD4<Float>(
//                -simd_dot(x, eye),
//                -simd_dot(y, eye),
//                -simd_dot(z, eye),
//                1
//            )
//        )
//    }
//
//    init(
//        perspectiveFov fov: Float,
//        aspect: Float,
//        nearZ: Float,
//        farZ: Float
//    ) {
//
//        let yScale =
//            1 / tan(fov * 0.5)
//
//        let xScale =
//            yScale / aspect
//
//        let zRange =
//            farZ - nearZ
//
//        self.init(
//            SIMD4<Float>(
//                xScale, 0, 0, 0
//            ),
//
//            SIMD4<Float>(
//                0, yScale, 0, 0
//            ),
//
//            SIMD4<Float>(
//                0,
//                0,
//                -(farZ + nearZ) / zRange,
//                -1
//            ),
//
//            SIMD4<Float>(
//                0,
//                0,
//                -(2 * farZ * nearZ) / zRange,
//                0
//            )
//        )
//    }
//}
