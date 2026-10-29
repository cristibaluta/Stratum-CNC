//
//  EntryDiagram.swift
//  Stratum CNC
//
//  The drawing in the entry strategy popover, in the same style as `LeadInOutDiagram`: a
//  rounded panel, the material to remove hatched, the move of the tool in the accent colour
//  with a dot running along it. It is a side view (the entry is about depth), in mm, zoomed to the entry itself so a
//  small stepdown (0.1 mm) still shows its ramp or helix across the width. Horizontally it
//  is always to scale, with a scale bar. Vertically it is to scale too, unless the stepdown
//  would be too thin to see, and then only the depth is stretched.
//

import SwiftUI

struct EntryDiagram: View {
    let type: RampType
    /// Degrees from the surface (linear ramp, helix). A plunge is always 90°.
    let angle: Double
    /// mm: the depth one pass goes down, which is what the entry has to cover.
    let stepdown: Double
    /// mm. Zero (no tool picked yet) draws a 6 mm tool.
    let toolDiameter: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = phase(for: timeline.date, cycleDuration: 2.8)
            Canvas { context, size in
                draw(in: &context, size: size, time: time)
            }
        }
        .frame(height: 190)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemFill)))
        .accessibilityLabel("Entry strategy drawing")
    }

    // MARK: Geometry (world space, mm, y up, the stock surface on y = 0)

    private struct Scene {
        var path: [CGPoint]     // where the tool tip goes while it enters
        var depth: Double
        var diameter: Double
        var turns: Double       // helix only
    }

    private func makeScene() -> Scene {
        let diameter = toolDiameter > 0 ? toolDiameter : 6
        let depth = max(stepdown, 0.01)
        let slope = RampMath.clampedAngle(angle)

        var path: [CGPoint] = []
        var turns = 0.0

        switch type {
            case .none:
                path = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: -depth)]

            case .linear:
                // Out along the slope for half the distance, then back along it to the start
                // point, so the cut begins at full depth where it began (see `RampingEditor`).
                let half = RampMath.linearRequiredLength(angle: slope, stepdown: depth) / 2
                path = [CGPoint(x: 0, y: 0),
                        CGPoint(x: half, y: -depth / 2),
                        CGPoint(x: 0, y: -depth)]

            case .helix:
                // Seen from the side a helix is a wave going down. A small stepdown is only a
                // fraction of a turn; a very large one is cut off at a few turns.
                turns = min(RampMath.helixTurnsNeeded(angle: slope, diameter: diameter, stepdown: depth), 8)
                let radius = RampMath.helixDiameter(toolDiameter: diameter) / 2
                let steps = max(Int(turns * 48), 12)
                for i in 0...steps {
                    let f = Double(i) / Double(steps)
                    let theta = 2 * Double.pi * turns * f
                    path.append(CGPoint(x: -radius * cos(theta), y: -depth * f))
                }
        }

        let end = path.last ?? .zero
        return Scene(path: path, depth: depth, diameter: diameter, turns: turns)
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, time: CGFloat) {
        let scene = makeScene()
        let radius = CGFloat(scene.diameter / 2)
        let start = scene.path.first ?? .zero

        // Zoom to the entry: the path fills the width. A plunge has
        // no width of its own, so it is framed by the tool.
        var xs = scene.path.map(\.x)
        if type == .none {
            xs += [start.x - radius * 0.8, start.x + radius * 0.8]
        }
        let minX: CGFloat = xs.min() ?? 0
        let maxX: CGFloat = xs.max() ?? 1

        let padding: CGFloat = 22
        let availableWidth: CGFloat = size.width - 2 * padding - 20     // room for the dimension line
        let surfaceY: CGFloat = size.height * 0.34
        let maxLayer: CGFloat = size.height * 0.40                      // the layer may take this much height
        let minLayer: CGFloat = 34                                      // and should show at least this much
        let depth = CGFloat(scene.depth)

        // One scale for both axes where possible (so slopes are true). When the stepdown is too
        // thin to see at that scale, only the vertical is stretched.
        var scaleX = availableWidth / max(maxX - minX, 0.0001)
        if scaleX * depth > maxLayer {
            scaleX = maxLayer / depth
        }
        var scaleY = scaleX
        if scaleX * depth < minLayer {
            scaleY = min(minLayer, maxLayer) / depth
        }
        let originX: CGFloat = padding + (availableWidth - (maxX - minX) * scaleX) / 2 - minX * scaleX

        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: originX + point.x * scaleX, y: surfaceY - point.y * scaleY)
        }

        func polyline(_ points: [CGPoint]) -> Path {
            var path = Path()
            for (index, point) in points.enumerated() {
                if index == 0 {
                    path.move(to: map(point))
                } else {
                    path.addLine(to: map(point))
                }
            }
            return path
        }

        let accent = Color.accentColor
        let floorY = surfaceY + depth * scaleY

        // Side view of the stock: the layer one pass takes off is hatched (still uncut), the
        // material under it stays.
        let layerRect = CGRect(x: 0, y: surfaceY, width: size.width, height: max(floorY - surfaceY, 0))
        let stayRect = CGRect(x: 0, y: floorY, width: size.width, height: max(size.height - floorY, 0))
        context.fill(Path(stayRect), with: .color(Color.secondary.opacity(0.30)))
        context.fill(Path(layerRect), with: .color(Color.orange.opacity(0.07)))
        do {
            var hatch = context
            hatch.clip(to: Path(layerRect))
            var lines = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 9
            }
            hatch.stroke(lines, with: .color(Color.orange.opacity(0.22)), style: StrokeStyle(lineWidth: 1))
        }
        context.stroke(Path { $0.move(to: CGPoint(x: 0, y: surfaceY)); $0.addLine(to: CGPoint(x: size.width, y: surfaceY)) },
                       with: .color(Color.primary.opacity(0.8)), style: StrokeStyle(lineWidth: 2))
        context.stroke(Path { $0.move(to: CGPoint(x: 0, y: floorY)); $0.addLine(to: CGPoint(x: size.width, y: floorY)) },
                       with: .color(Color.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1))

        context.draw(Text("SIDE VIEW").font(.system(size: 9, weight: .semibold)).foregroundColor(Color.secondary),
                     at: CGPoint(x: size.width - 8, y: 10), anchor: .trailing)
        context.draw(Text("Material (stays)").font(.system(size: 10, weight: .medium)).foregroundColor(Color.secondary),
                     at: CGPoint(x: 8, y: size.height - 10), anchor: .leading)

        // How deep one pass goes: a dimension line at the right edge.
        let dimX = size.width - 14
        context.stroke(Path { path in
            path.move(to: CGPoint(x: dimX, y: surfaceY))
            path.addLine(to: CGPoint(x: dimX, y: floorY))
            path.move(to: CGPoint(x: dimX - 4, y: surfaceY))
            path.addLine(to: CGPoint(x: dimX + 4, y: surfaceY))
            path.move(to: CGPoint(x: dimX - 4, y: floorY))
            path.addLine(to: CGPoint(x: dimX + 4, y: floorY))
        }, with: .color(Color.secondary), style: StrokeStyle(lineWidth: 1))
        context.draw(Text("stepdown \(Self.format(scene.depth)) mm").font(.system(size: 9)).foregroundColor(Color.secondary),
                     at: CGPoint(x: dimX + 6, y: floorY + 10), anchor: .trailing)

        // The path of the tool tip while it enters.
        context.stroke(polyline(scene.path),
                       with: .color(accent),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        let screenPath = scene.path.map(map)
        let marker = map(start)

        // Where the entry starts, and the tool tip running along the path.
        let startDot = CGRect(x: marker.x - 3, y: marker.y - 3, width: 6, height: 6)
        context.fill(Path(ellipseIn: startDot), with: .color(Color.secondary))
        let running = point(along: screenPath, phase: time)
        let dot = CGRect(x: running.x - 5, y: running.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: dot), with: .color(accent))
        context.stroke(Path(ellipseIn: dot), with: .color(Color(.windowBackgroundColor)), style: StrokeStyle(lineWidth: 1.5))

        // How far the entry runs, measured along the surface, when it runs anywhere.
        if type != .none, let first = screenPath.map(\.x).min(), let last = screenPath.map(\.x).max(), last - first > 8 {
            let run = (scene.path.map(\.x).max() ?? 0) - (scene.path.map(\.x).min() ?? 0)
            let dimY = floorY + 30
            context.stroke(Path { path in
                // The line, and the dashed legs down to it from the two ends of the entry.
                path.move(to: CGPoint(x: first, y: dimY))
                path.addLine(to: CGPoint(x: last, y: dimY))
                path.move(to: CGPoint(x: first, y: dimY - 4))
                path.addLine(to: CGPoint(x: first, y: dimY + 4))
                path.move(to: CGPoint(x: last, y: dimY - 4))
                path.addLine(to: CGPoint(x: last, y: dimY + 4))
            }, with: .color(Color.secondary), style: StrokeStyle(lineWidth: 1))
            for x in [first, last] {
                let legTop = screenPath.min(by: { abs($0.x - x) < abs($1.x - x) })?.y ?? floorY
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: x, y: legTop + 6))
                    path.addLine(to: CGPoint(x: x, y: dimY - 4))
                }, with: .color(Color.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            context.draw(Text("\(Self.format(Double(run))) mm").font(.system(size: 10, weight: .medium)).foregroundColor(Color.secondary),
                         at: CGPoint(x: (first + last) / 2, y: dimY - 7), anchor: .bottom)
        }

        // The angle the tool goes down at, against the surface.
        switch type {
            case .none:
                let side: CGFloat = 9
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: marker.x + side, y: marker.y))
                    path.addLine(to: CGPoint(x: marker.x + side, y: marker.y + side))
                    path.addLine(to: CGPoint(x: marker.x, y: marker.y + side))
                }, with: .color(accent), style: StrokeStyle(lineWidth: 1.2))
                context.draw(Text("90°").font(.system(size: 10, weight: .semibold)).foregroundColor(accent),
                             at: CGPoint(x: marker.x + side + 8, y: marker.y - 8), anchor: .leading)

            case .linear:
                let degrees = RampMath.clampedAngle(angle)
                // The arc follows the slope as drawn, which is steeper than the real angle
                // when the depth is stretched; the label always gives the real angle.
                let second = screenPath.count > 1 ? screenPath[1] : marker
                let drawn = Double(atan2(second.y - marker.y, second.x - marker.x))
                let arcRadius: CGFloat = 34
                var arc = Path()
                let steps = 16
                for i in 0...steps {
                    let theta = drawn * Double(i) / Double(steps)
                    let point = CGPoint(x: marker.x + arcRadius * CGFloat(cos(theta)), y: marker.y + arcRadius * CGFloat(sin(theta)))
                    if i == 0 { arc.move(to: point) } else { arc.addLine(to: point) }
                }
                context.stroke(arc, with: .color(accent), style: StrokeStyle(lineWidth: 1.2))
                context.draw(Text("\(Self.format(degrees))°").font(.system(size: 10, weight: .semibold)).foregroundColor(accent),
                             at: CGPoint(x: marker.x + arcRadius + 6, y: marker.y - 8), anchor: .leading)

            case .helix:
                break
        }
    }

    // MARK: Helpers

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }
}

#Preview {
    VStack {
        EntryDiagram(type: .none, angle: 3, stepdown: 2, toolDiameter: 6)
        EntryDiagram(type: .linear, angle: 3, stepdown: 1, toolDiameter: 6)
        EntryDiagram(type: .helix, angle: 3, stepdown: 2, toolDiameter: 6)
    }
    .padding()
    .frame(width: 400)
}
