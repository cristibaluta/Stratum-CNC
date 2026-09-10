//
//  MotionType.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 10.09.2026.
//

import Foundation
import simd

//public enum MotionType: Sendable {
//    case rapid                 // G0 (Safe height moves)
//    case linear                // G1 (Cutting move)
//    case arcCW(center: CGPoint)  // G2
//    case arcCCW(center: CGPoint) // G3
//}
//
//public struct ToolpathPoint: Sendable {
//    public let position: SIMD3<Double> // X, Y, Z
//    public let motion: MotionType
//    public let feedRate: Double
//}
//
///// A fully calculated pass sequence ready for display or execution
//struct ComputedToolpath: Sendable {
//    public let operationID: UUID
//    public let tool: Tool
//    public let passes: [[ToolpathPoint]] // Structured by Z-level depth passes
//    
//    /// Bounding box for preview rendering
//    public var totalPathLength: Double { 0 }
//}
//
//struct CAMJob: Sendable {
//    public var operations: [Operation]
//    public var generatedToolpaths: [ComputedToolpath]
//}
