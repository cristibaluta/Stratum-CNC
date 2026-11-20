//
//  SetupStockExtents.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.11.2026.
//

import Foundation

/// What `SetupFrame` needs to know about the stock, in the part's frame.
struct SetupStockExtents {
    /// Size along X (left to right), Y (front to back) and Z (thickness), mm.
    let x: Double
    let y: Double
    let z: Double
    /// Where the stock's centre lines sit in X and Y on the canvas.
    let centerX: Double
    let centerY: Double
    /// A rectangular block, which can be stood on any of its four long sides.
    let isBox: Bool
}

extension StockMaterial {

    /// ASSUMPTION to check: the stock sits with its front-left corner at X = 0, Y = 0 and its top at
    /// Z = 0 (the same z0 the toolpaths are cut from), so its centre lines are at `x / 2` and `y / 2`. If the canvas
    /// centres the stock on the origin instead, return 0 for `centerX` and `centerY`: it is the only
    /// place that knows.
    var setupExtents: SetupStockExtents {
        switch geometry {
            case .rectangular(let length, let width, let height):

                return SetupStockExtents(x: length,
                                         y: width,
                                         z: height,
                                         centerX: length / 2,
                                         centerY: width / 2,
                                         isBox: true)

            case .cylindrical(let diameter, let length):

                return SetupStockExtents(x: diameter,
                                         y: diameter,
                                         z: length,
                                         centerX: diameter / 2,
                                         centerY: diameter / 2,
                                         isBox: false)

            case .disk(let outerDiameter, _, let height):

                return SetupStockExtents(x: outerDiameter,
                                         y: outerDiameter,
                                         z: height,
                                         centerX: outerDiameter / 2,
                                         centerY: outerDiameter / 2,
                                         isBox: false)
        }
    }
}
