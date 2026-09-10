//
//  VectorPath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 10.09.2026.
//

import Foundation

/// A clean 2D vector path composed of explicit linear and circular arc segments
//public struct VectorPath: Sendable {
//    public enum Segment: Sendable {
//        case line(start: CGPoint, end: CGPoint)
//        case arc(center: CGPoint, radius: Double, startAngle: Double, endAngle: Double, isCCW: Bool)
//    }
//    
//    public var segments: [Segment]
//    public var isClosed: Bool
//    public var bounds: CGRect
//}
//
//public struct ToolParams: Sendable {
//    public let id: UUID
//    public let name: String
//    public let diameter: Double
//    public let stepoverPercentage: Double // 0.1 ... 0.9 (e.g. 50% = 0.5)
//    public let stepdown: Double // Max depth per pass (Z)
//}
//
//public struct CuttingParams: Sendable {
//    public var feedRate: Double // mm/min or inch/min
//    public var plungeRate: Double // Z-down feed rate
//    public var spindleRPM: Double
//    public var targetDepth: Double // Total cut depth (negative Z)
//    public var safeZ: Double // Retraction height
//}
//
//public enum CutSide: Sendable {
//    case inside
//    case outside
//    case onPath
//}
//
//public enum OperationType: Sendable {
//    /// Follow geometry directly (Engraving / V-Carving)
//    case engrave
//    /// Offset geometry inside or outside (Contour Cut)
//    case profile(side: CutSide)
//    /// Clear internal volume bounded by closed paths
//    case pocket(strategy: PocketStrategy)
//}
//
//public enum PocketStrategy: Sendable {
//    case raster(angleDeg: Double)
//    case contourParallel
//}
//
//struct Operation: Sendable {
//    public let id: UUID
//    public let name: String
//    public let type: OperationType
//    public let tool: ToolParams
//    public let params: CuttingParams
//    public var sourcePaths: [VectorPath]
//}
