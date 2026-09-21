//
//  SVGPathHitTester.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//
//  The CALayer-based overload that used to live here (against
//  `[UUID: D2_ObjectNode]` / `CALayer`) was CAM_2D_View's hit testing and
//  was removed in step 6 along with `D2_CanvasNSView` / `D2_ObjectNode`.
//  The surviving `hitTest(worldPoint:paths:pointsPerWorldUnit:)` overload
//  is in PathHitTester+World.swift.
//

import Foundation
import QuartzCore

struct PathHitTester {

    let tolerance: CGFloat
}
