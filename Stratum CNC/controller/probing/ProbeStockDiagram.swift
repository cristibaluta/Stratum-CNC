//
//  ProbeStockDiagram.swift
//  Stratum CNC
//
//  The 2D drawings of the probing dialog. They are schematics, not to scale:
//  the probe is never told a size.
//
//    ProbeFeatureDrawing  a boss or a pocket seen from above, with the dot and
//                         the touches, used for the tiles on the first step
//    ProbeZDrawing        the probe tip over a surface, for the Z mode
//    ProbeStockDiagram    the larger drawing of the position step, where the
//                         corner is chosen and the dot pulses
//
//  Drawn in the work frame: X to the right, Y up. On the machine home is at
//  the back (see `MachineLayout`), so the front, where the person stands, is
//  at the bottom of the drawing.
//

import SwiftUI

// MARK: - Where everything sits

/// The positions of a drawing, computed once so the static drawing and the
/// interactive diagram agree.
struct ProbeSchematic {

    let plate: CGRect
    /// The boss or the pocket.
    let shape: CGRect
    let isRound: Bool
    /// Where the tip is jogged to.
    let dot: CGPoint
    /// Where the probe will touch the outline.
    let touches: [CGPoint]
    /// The four corners of `shape`, for the corner features.
    let corners: [ProbePoint: CGPoint]

    init(feature: ProbeFeature, corner: ProbePoint, in size: CGSize) {
        plate = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
        isRound = feature.isCenter

        if feature.isCenter {
            let side = min(plate.width, plate.height) * 0.55
            shape = CGRect(x: plate.midX - side / 2, y: plate.midY - side / 2, width: side, height: side)
            dot = CGPoint(x: shape.midX, y: shape.midY)
            touches = [CGPoint(x: shape.minX, y: shape.midY),
                       CGPoint(x: shape.maxX, y: shape.midY),
                       CGPoint(x: shape.midX, y: shape.minY),
                       CGPoint(x: shape.midX, y: shape.maxY)]
            corners = [:]
        } else {
            let width = plate.width * 0.5
            let height = plate.height * 0.55
            shape = CGRect(x: plate.midX - width / 2, y: plate.midY - height / 2, width: width, height: height)

            var points: [ProbePoint: CGPoint] = [:]
            points[.bottomLeft] = CGPoint(x: shape.minX, y: shape.maxY)
            points[.bottomRight] = CGPoint(x: shape.maxX, y: shape.maxY)
            points[.topLeft] = CGPoint(x: shape.minX, y: shape.minY)
            points[.topRight] = CGPoint(x: shape.maxX, y: shape.minY)
            corners = points

            let anchor = points[corner] ?? points[.bottomLeft] ?? .zero
            let inset = min(shape.width, shape.height) * 0.4
            dot = CGPoint(x: anchor.x + (corner.column < 0 ? inset : -inset),
                          y: anchor.y + (corner.row < 0 ? -inset : inset))
            touches = [CGPoint(x: anchor.x, y: dot.y),
                       CGPoint(x: dot.x, y: anchor.y)]
        }
    }
}

// MARK: - Boss or pocket from above

struct ProbeFeatureDrawing: View {

    let feature: ProbeFeature
    var corner: ProbePoint = .bottomLeft
    /// The tiles draw the dot themselves; the position step lets it pulse.
    var showsDot = true

    var body: some View {
        Canvas { context, size in
            let layout = ProbeSchematic(feature: feature, corner: corner, in: size)
            let line = GraphicsContext.Shading.color(.secondary)
            let accent = GraphicsContext.Shading.color(.accentColor)

            // The same colors for all four: a dark plate and a lighter shape.
            // A boss also gets a drop shadow to stand on the plate.
            let plate = Path(roundedRect: layout.plate, cornerRadius: 5)
            context.fill(plate, with: .color(Color.secondary.opacity(0.45)))
            context.stroke(plate, with: .color(Color.secondary.opacity(0.6)), lineWidth: 1)

            let outline = layout.isRound
                ? Path(ellipseIn: layout.shape)
                : Path(roundedRect: layout.shape, cornerRadius: 2)
            if !feature.isInside {
                context.fill(outline.offsetBy(dx: 4, dy: 4), with: .color(Color.black.opacity(0.22)))
            }
            context.fill(outline, with: .color(Color.white.opacity(0.6)))
            if feature.isInside {
                // An inner shadow, only inside the pocket: the outline shifted
                // down and right leaves a strip along its top and left walls.
                context.drawLayer { layer in
                    layer.clip(to: outline)
                    var strip = Path(layout.plate)
                    strip.addPath(outline.offsetBy(dx: 4, dy: 4))
                    layer.fill(strip, with: .color(Color.black.opacity(0.22)), style: FillStyle(eoFill: true))
                }
            }
            context.stroke(outline, with: line, lineWidth: 1.5)

            // Dashed lines from the dot to the touches, with an arrowhead on
            // the outline: out to the wall for a pocket, in from outside for a boss.
            for touch in layout.touches {
                var path = Path()
                path.move(to: layout.dot)
                path.addLine(to: touch)
                context.stroke(path, with: accent, style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                context.stroke(Self.arrowHead(at: touch, from: layout.dot, pointsOut: feature.isInside),
                               with: accent, lineWidth: 1.8)
            }

            if showsDot {
                let outer = Path(ellipseIn: CGRect(x: layout.dot.x - 7, y: layout.dot.y - 7, width: 14, height: 14))
                let inner = Path(ellipseIn: CGRect(x: layout.dot.x - 4.5, y: layout.dot.y - 4.5, width: 9, height: 9))
                context.fill(outer, with: .color(Color(white: 1, opacity: 0.9)))
                context.fill(inner, with: accent)
            }
        }
    }

    /// A small arrowhead on the dashed line, with its tip on the outline. For
    /// a pocket the probe moves out toward the wall, so it points at the wall;
    /// for a boss it comes in from outside, so it points at the center.
    private static func arrowHead(at tip: CGPoint, from dot: CGPoint, pointsOut: Bool) -> Path {
        let dx = tip.x - dot.x
        let dy = tip.y - dot.y
        let length = max((dx * dx + dy * dy).squareRoot(), 1)
        let out = CGPoint(x: dx / length, y: dy / length)
        let direction = pointsOut ? out : CGPoint(x: -out.x, y: -out.y)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let size: CGFloat = 7

        var path = Path()
        path.move(to: CGPoint(x: tip.x - direction.x * size + normal.x * size * 0.6,
                              y: tip.y - direction.y * size + normal.y * size * 0.6))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x - direction.x * size - normal.x * size * 0.6,
                                 y: tip.y - direction.y * size - normal.y * size * 0.6))
        return path
    }
}

// MARK: - Z

/// The probe tip above a surface, moving down. Side view.
struct ProbeZDrawing: View {

    var body: some View {
        Canvas { context, size in
            let line = GraphicsContext.Shading.color(.secondary)
            let accent = GraphicsContext.Shading.color(.accentColor)

            // The surface.
            let block = CGRect(x: size.width * 0.12, y: size.height * 0.66,
                               width: size.width * 0.76, height: size.height * 0.26)
            let blockPath = Path(roundedRect: block, cornerRadius: 3)
            context.fill(blockPath, with: .color(Color.secondary.opacity(0.22)))
            context.stroke(blockPath, with: line, lineWidth: 1.5)

            // The probe: a shank and a ball.
            let midX = size.width / 2
            let ballRadius: CGFloat = 8
            let ballY = size.height * 0.36
            let shank = CGRect(x: midX - 5, y: size.height * 0.06, width: 10, height: ballY - size.height * 0.06)
            context.fill(Path(roundedRect: shank, cornerRadius: 2), with: .color(Color.secondary.opacity(0.45)))
            let ball = Path(ellipseIn: CGRect(x: midX - ballRadius, y: ballY - ballRadius,
                                              width: ballRadius * 2, height: ballRadius * 2))
            context.fill(ball, with: .color(Color.primary.opacity(0.7)))

            // The way down.
            let top = ballY + ballRadius + 6
            let bottom = block.minY - 3
            var arrow = Path()
            arrow.move(to: CGPoint(x: midX, y: top))
            arrow.addLine(to: CGPoint(x: midX, y: bottom))
            context.stroke(arrow, with: accent, style: StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
            var head = Path()
            head.move(to: CGPoint(x: midX - 5, y: bottom - 7))
            head.addLine(to: CGPoint(x: midX, y: bottom))
            head.addLine(to: CGPoint(x: midX + 5, y: bottom - 7))
            context.stroke(head, with: accent, lineWidth: 1.8)
        }
    }
}

// MARK: - The two probes

/// A probe seen from the side: the body, the stylus and the ball.
struct ProbeHardwareDrawing: View {

    let hardware: ProbeHardware

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let ballRadius: CGFloat = 13
            let ballY = size.height * 0.72

            // Body.
            let body = CGRect(x: midX - 16, y: size.height * 0.08, width: 32, height: size.height * 0.34)
            let bodyPath = Path(roundedRect: body, cornerRadius: 5)
            context.fill(bodyPath, with: .color(Color.secondary.opacity(0.45)))
            context.stroke(bodyPath, with: .color(Color.secondary), lineWidth: 1.2)

            // Stylus.
            var stylus = Path()
            stylus.move(to: CGPoint(x: midX, y: body.maxY))
            stylus.addLine(to: CGPoint(x: midX, y: ballY - ballRadius))
            context.stroke(stylus, with: .color(Color.secondary), lineWidth: 3)

            // Ball: silver for the metal probe, red for the ruby.
            let ball = Path(ellipseIn: CGRect(x: midX - ballRadius, y: ballY - ballRadius,
                                              width: ballRadius * 2, height: ballRadius * 2))
            let color: Color = hardware == .ruby ? Color(red: 0.8, green: 0.1, blue: 0.2) : Color(white: 0.78)
            context.fill(ball, with: .color(color))
            context.stroke(ball, with: .color(Color.black.opacity(0.35)), lineWidth: 1)
            let shine = Path(ellipseIn: CGRect(x: midX - 7, y: ballY - 8, width: 6, height: 6))
            context.fill(shine, with: .color(Color.white.opacity(0.7)))
        }
    }
}

// MARK: - Position step

struct ProbeStockDiagram: View {

    @Binding var flow: ProbeFlow

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if flow.kind == .zSurface {
                    ProbeZDrawing()
                        .padding(40)
                } else {
                    let layout = ProbeSchematic(feature: flow.feature, corner: flow.corner, in: proxy.size)

                    ProbeFeatureDrawing(feature: flow.feature, corner: flow.corner, showsDot: false)
                    handles(layout)

                    PulsingDot()
                        .position(layout.dot)
                        .animation(.easeInOut(duration: 0.25), value: layout.dot)

                    axes(in: proxy.size)
                    frontLabel(in: proxy.size)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    // MARK: Choosing a corner

    /// The four corners of the boss or pocket, for the corner features. A
    /// center has nothing to choose.
    @ViewBuilder
    private func handles(_ layout: ProbeSchematic) -> some View {
        if flow.choosesCorner {
            ForEach([ProbePoint.topLeft, .topRight, .bottomLeft, .bottomRight]) { point in
                if let position = layout.corners[point] {
                    handle(isSelected: point == flow.corner,
                           help: point.title(inside: flow.isInside)) {
                        flow.corner = point
                    }
                    .position(position)
                }
            }
        }
    }

    private func handle(isSelected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(isSelected ? Color.accentColor : Color(white: 0.5, opacity: 0.001))
                Circle().strokeBorder(isSelected ? Color.accentColor : Color.secondary, lineWidth: 2)
            }
            .frame(width: 14, height: 14)
            .padding(9)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Orientation

    private func axes(in size: CGSize) -> some View {
        let origin = CGPoint(x: 18, y: size.height - 18)
        return ZStack {
            Path { path in
                path.move(to: origin)
                path.addLine(to: CGPoint(x: origin.x + 26, y: origin.y))
                path.move(to: origin)
                path.addLine(to: CGPoint(x: origin.x, y: origin.y - 26))
            }
            .stroke(Color.secondary, lineWidth: 1.2)
            Text("X").position(x: origin.x + 36, y: origin.y)
            Text("Y").position(x: origin.x, y: origin.y - 36)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .allowsHitTesting(false)
    }

    private func frontLabel(in size: CGSize) -> some View {
        Text("FRONT OF MACHINE")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .position(x: size.width / 2, y: size.height - 10)
            .allowsHitTesting(false)
    }
}

/// A solid dot with a ring that grows and fades, repeating. With Reduce
/// Motion on, the ring stays still.
private struct PulsingDot: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 16, height: 16)
                .scaleEffect(isPulsing && !reduceMotion ? 2.6 : 1)
                .opacity(reduceMotion ? 0.5 : (isPulsing ? 0 : 0.9))
                .animation(reduceMotion ? nil : .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                           value: isPulsing)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
        }
        .onAppear { isPulsing = true }
        .allowsHitTesting(false)
        .help("Jog the probe tip above this point")
    }
}
