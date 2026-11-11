//
//  CalloutShape.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 11.11.2026.
//

import SwiftUI

/// A rounded rectangle with a downward arrow centered on its bottom edge, as one
/// outline so the fill and the stroke have no seam where the arrow joins.
struct CalloutShape: Shape {

    var cornerRadius: CGFloat = 10
    let arrowSize: CGSize

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let bottom = rect.maxY - arrowSize.height
        let midX = rect.midX

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r),
                 radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom),
                 tangent2End: CGPoint(x: rect.maxX - r, y: bottom),
                 radius: r)
        // The arrow
        p.addLine(to: CGPoint(x: midX + arrowSize.width / 2, y: bottom))
        p.addLine(to: CGPoint(x: midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: midX - arrowSize.width / 2, y: bottom))
        p.addLine(to: CGPoint(x: rect.minX + r, y: bottom))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom),
                 tangent2End: CGPoint(x: rect.minX, y: bottom - r),
                 radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + r, y: rect.minY),
                 radius: r)
        p.closeSubpath()

        return p
    }
}
