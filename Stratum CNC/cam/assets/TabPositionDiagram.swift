//
//  TabPositionDiagram.swift
//  Stratum CNC
//
//  Custom drawing, moved out of HoldingTabsButton.swift.
//

import SwiftUI

/// A closed contour with one numbered marker per tab, placed by its position ratio: the
/// selected shape when there is one, otherwise a schematic rounded rectangle. A ratio is a
/// fraction of the outline's length counted from where it starts (the start of its path), so
/// 0.25 is a quarter of the way round, 0.5 halfway. The tool actually follows the shape
/// offset by its radius, and the engine decides the real start and direction, so the markers
/// are an approximation.
struct TabPositionDiagram: View {
    let tabs: [HoldingTabSettings]
    /// The outline in world space (y up); `nil` draws the schematic.
    var shape: CGPath? = nil

    private static let corner: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 24, dy: 18)
            let path = shape.map { Self.fit(Path($0), in: rect) } ?? Self.contourPath(in: rect)
            let start = Self.point(on: path, at: 0)
            ZStack {
                path.stroke(Color.secondary.opacity(0.6),
                            style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                if shape == nil {
                    Text("0 → 1 along the contour\n0.5 = halfway round")
                        .font(.system(size: 10))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .position(x: rect.midX, y: rect.midY)
                }

                // Where the outline starts (position 0, and also 1), with the way it runs
                Self.arrow(on: path)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 1.5)
                    .background(Circle().fill(Color(.windowBackgroundColor)))
                    .frame(width: 7, height: 7)
                    .position(start)
                Text("Start")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .position(x: start.x, y: start.y - 11)

                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.accentColor))
                        .position(Self.point(on: path, at: tab.positionRatio))
                }
            }
        }
        .frame(height: shape == nil ? 100 : 150)
        .accessibilityLabel("Tab positions along the contour")
    }

    /// `path` scaled to fit `rect` (keeping its proportions, centred) and flipped, because the
    /// shape's Y points up and the screen's down.
    private static func fit(_ path: Path, in rect: CGRect) -> Path {
        let box = path.boundingRect
        guard box.width > 0 || box.height > 0 else {
            return path
        }
        let scale = min(rect.width / max(box.width, 0.0001), rect.height / max(box.height, 0.0001))
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: rect.midX, y: rect.midY)
        transform = transform.scaledBy(x: scale, y: -scale)
        transform = transform.translatedBy(x: -box.midX, y: -box.midY)
        return path.applying(transform)
    }

    /// A rounded rectangle, started at the top edge and run clockwise.
    private static func contourPath(in rect: CGRect) -> Path {
        let r = corner
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }

    /// The point `ratio` (0...1) of the way along the path's length.
    private static func point(on path: Path, at ratio: Double) -> CGPoint {
        let end = min(max(ratio, 0.0001), 1)
        return path.trimmedPath(from: 0, to: end).currentPoint ?? .zero
    }

    /// A small arrowhead a little way along the outline, pointing the way ratios increase.
    private static func arrow(on path: Path) -> Path {
        let tail = point(on: path, at: 0.02)
        let tip = point(on: path, at: 0.035)
        let dx = tip.x - tail.x
        let dy = tip.y - tail.y
        let length = hypot(dx, dy)
        guard length > 0.001 else {
            return Path()
        }
        let ux = dx / length
        let uy = dy / length
        let size: CGFloat = 5
        var arrow = Path()
        arrow.move(to: CGPoint(x: tip.x - ux * size - uy * size * 0.6, y: tip.y - uy * size + ux * size * 0.6))
        arrow.addLine(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x - ux * size + uy * size * 0.6, y: tip.y - uy * size - ux * size * 0.6))
        return arrow
    }
}
