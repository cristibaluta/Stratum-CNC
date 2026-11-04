//
//  ProbeStockDiagram.swift
//  Stratum CNC
//
//  The thing being probed seen from above, drawn to scale (the stock, or the
//  pocket or hole when probing the inside), with the pulsing dot that marks
//  where the probe tip should be jogged to. The dot is a target, not the
//  probe's position: the drawing does not know where the probe is.
//
//  Drawn in the work frame: X to the right, Y up. On the machine home is at
//  the back (see `MachineLayout`), so the front, where the person stands, is
//  at the bottom of the drawing.
//

import SwiftUI

struct ProbeStockDiagram: View {

    @Binding var flow: ProbeFlow
    /// The "start inset" setting: how far the dot sits from the corner or side.
    let inset: Double

    private let margin: CGFloat = 44

    // MARK: Layout

    /// Maps feature coordinates (origin bottom-left, Y up) to points in the view.
    private struct Layout {
        let rect: CGRect
        let scale: CGFloat

        init(width: Double, height: Double, in size: CGSize, margin: CGFloat) {
            let availableWidth = max(size.width - 2 * margin, 10)
            let availableHeight = max(size.height - 2 * margin, 10)
            scale = min(availableWidth / CGFloat(max(width, 1)), availableHeight / CGFloat(max(height, 1)))
            let drawnWidth = CGFloat(width) * scale
            let drawnHeight = CGFloat(height) * scale
            rect = CGRect(x: (size.width - drawnWidth) / 2,
                          y: (size.height - drawnHeight) / 2,
                          width: drawnWidth,
                          height: drawnHeight)
        }

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(x) * scale, y: rect.maxY - CGFloat(y) * scale)
        }
    }

    private var size: (width: Double, height: Double) {
        flow.featureSize
    }

    // MARK: Body

    var body: some View {
        GeometryReader { proxy in
            let layout = Layout(width: size.width, height: size.height, in: proxy.size, margin: margin)
            let target = flow.targetPoint(inset: inset)
            let dot = layout.point(target.x, target.y)

            ZStack {
                stock(layout)
                dimensionLabels(layout)
                touchHints(layout, from: dot)
                handles(layout)

                PulsingDot()
                    .position(dot)
                    .animation(.easeInOut(duration: 0.25), value: dot)

                axes(in: proxy.size)
                frontLabel(in: proxy.size)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    // MARK: Stock

    private let stockFill = Color.secondary.opacity(0.18)
    private let stockLine = Color.secondary

    @ViewBuilder
    private func stock(_ layout: Layout) -> some View {
        if flow.isInside {
            pocket(layout)
        } else {
            outsideStock(layout)
        }
    }

    /// The inside of a pocket or hole: an empty shape with a dashed outline,
    /// because the stock around it is not what is being touched.
    @ViewBuilder
    private func pocket(_ layout: Layout) -> some View {
        let path = flow.shape == .circle
            ? Path(ellipseIn: layout.rect)
            : Path(roundedRect: layout.rect, cornerRadius: 2)
        path.fill(Color.primary.opacity(0.06))
        path.stroke(stockLine, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
    }

    @ViewBuilder
    private func outsideStock(_ layout: Layout) -> some View {
        if flow.isRoundBoss {
            let path = Path(ellipseIn: layout.rect)
            path.fill(stockFill)
            path.stroke(stockLine, lineWidth: 1.5)
        } else {
            stockOfGeometry(layout)
        }
    }

    @ViewBuilder
    private func stockOfGeometry(_ layout: Layout) -> some View {
        switch flow.geometry {
            case .rectangular, .cylindrical:
                let path = Path(roundedRect: layout.rect, cornerRadius: 3)
                path.fill(stockFill)
                path.stroke(stockLine, lineWidth: 1.5)
            case let .disk(_, innerDiameter, _):
                let outer = layout.rect
                let innerSide = CGFloat(innerDiameter) * layout.scale
                let inner = CGRect(x: outer.midX - innerSide / 2, y: outer.midY - innerSide / 2,
                                   width: innerSide, height: innerSide)
                let path = Path { path in
                    path.addEllipse(in: outer)
                    if innerDiameter > 0 { path.addEllipse(in: inner) }
                }
                // Even-odd fill leaves the hole empty.
                path.fill(stockFill, style: FillStyle(eoFill: true))
                path.stroke(stockLine, lineWidth: 1.5)
        }
    }

    private func dimensionLabels(_ layout: Layout) -> some View {
        let isRound = flow.shape == .circle
        let name = flow.isInside ? (flow.hasHole ? "Hole " : "Pocket ") : (flow.isRoundBoss ? "Boss " : "")
        let widthText = name + (isRound ? "Ø\(ProbeFlow.mm(size.width)) mm" : "\(ProbeFlow.mm(size.width)) mm")
        return ZStack {
            Text(widthText)
                .position(x: layout.rect.midX, y: layout.rect.minY - 24)
            if !isRound {
                Text("\(ProbeFlow.mm(size.height)) mm")
                    .rotationEffect(.degrees(-90))
                    .position(x: layout.rect.minX - 26, y: layout.rect.midY)
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    // MARK: What will be touched

    /// Dashed lines from the dot to the points on the outline that will be touched.
    private func touchHints(_ layout: Layout, from dot: CGPoint) -> some View {
        ZStack {
            ForEach(Array(flow.touchPoints(inset: inset).enumerated()), id: \.offset) { _, touch in
                let end = layout.point(touch.x, touch.y)
                Path { path in
                    path.move(to: dot)
                    path.addLine(to: end)
                }
                .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))

                Circle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                    .position(end)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Choosing a point

    /// The nine points of a rectangle: four corners, four side midpoints and
    /// the center. A round feature only has its center, so nothing to choose.
    @ViewBuilder
    private func handles(_ layout: Layout) -> some View {
        if flow.choosesPoint {
            ForEach(ProbePoint.allCases) { point in
                handle(isSelected: point == flow.point, help: point.title(inside: flow.isInside)) {
                    flow.point = point
                }
                .position(layout.point(x(of: point), y(of: point)))
            }
        }
    }

    private func x(of point: ProbePoint) -> Double {
        point.column < 0 ? 0 : (point.column > 0 ? size.width : size.width / 2)
    }

    private func y(of point: ProbePoint) -> Double {
        point.row < 0 ? 0 : (point.row > 0 ? size.height : size.height / 2)
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
