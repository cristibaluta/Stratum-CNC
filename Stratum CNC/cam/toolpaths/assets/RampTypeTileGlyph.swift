//
//  RampTypeTileGlyph.swift
//  Stratum CNC
//
//  Custom drawing, moved out of RampingButton.swift.
//

import SwiftUI

/// Tile-sized artwork for the expanded ramp picker: a part boundary against the
/// entry path, same convention as `ContourTypeGlyph` / `DirectionGlyph` /
/// `PatternGlyph` — separate from `RampTypeGlyph` above, which is drawn for the
/// much smaller compact trigger and doesn't carry a boundary at that size.
struct RampTypeTileGlyph: View {
    let type: RampType
    var tint: Color = .primary

    private let partInset: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            entryPath(in: proxy.size)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2, 1.6]))
        }
    }

    private func entryPath(in size: CGSize) -> Path {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: partInset + 4, dy: partInset + 3)
        switch type {
            case .none:   return plungePath(in: rect)
            case .linear: return linearPath(in: rect)
            case .helix:  return helixPath(in: rect)
        }
    }

    /// Straight down, no ramp.
    private func plungePath(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        return path
    }

    /// A straight diagonal ramp down to the floor.
    private func linearPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }

    /// A tightening spiral down to the floor, seen from the side as nested arcs.
    private func helixPath(in rect: CGRect) -> Path {
        var path = Path()
        let turns = 3
        let step = rect.height / CGFloat(turns * 2)
        for i in 0..<(turns * 2) {
            let y0 = rect.minY + CGFloat(i) * step
            let y1 = y0 + step
            let x0 = i.isMultiple(of: 2) ? rect.minX : rect.maxX
            let x1 = i.isMultiple(of: 2) ? rect.maxX : rect.minX
            if i == 0 {
                path.move(to: CGPoint(x: x0, y: y0))
            }
            path.addQuadCurve(to: CGPoint(x: x1, y: y1),
                               control: CGPoint(x: i.isMultiple(of: 2) ? rect.maxX : rect.minX, y: (y0 + y1) / 2))
        }
        return path
    }
}
