//
//  HoldingTabsButton.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 27.10.2026.
//
//
//  The contour's holding tabs: a row in the Operation section that only summarises them
//  (read-only text), and the popover it opens, where each tab sits in its own group box.
//  Same pattern as `RampingButton` / `RampingEditor`.
//

import SwiftUI

/// Same look as `RampingButton`: a labelled pop-up button, here showing a summary of the tabs.
struct HoldingTabsButton: View {
    let tabs: [HoldingTabSettings]
    let action: () -> Void

    var body: some View {
        InspectorRow(label: "Tabs") {
            Button(action: action) {
                InspectorMenuLabel {
                    Text(summary)
                        .foregroundStyle(tabs.isEmpty ? .secondary : .primary)
                }
            }
            .buttonStyle(.plain)
            .help("Add, remove and size the holding tabs")
        }
    }

    /// "None", "3 tabs", or "3 tabs · 4 × 1.5 mm" when they are all the same size.
    private var summary: String {
        guard let first = tabs.first else {
            return "None"
        }
        let count = tabs.count == 1 ? "1 tab" : "\(tabs.count) tabs"
        let sameSize = tabs.allSatisfy { $0.width == first.width && $0.height == first.height }
        guard sameSize else {
            return count
        }
        return "\(count) · \(Self.format(first.width)) × \(Self.format(first.height)) mm"
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }
}

struct HoldingTabsEditor: View {
    @Binding var tabs: [HoldingTabSettings]

    /// The selected shapes' outlines, built when the popover is drawn. Empty when nothing is
    /// selected (or the facing covers the whole stock): the drawing is then a schematic.
    var shapes: () -> [CGPath] = { [] }

    /// Which of the shapes the drawing shows; one at a time.
    @State private var shapeIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Holding tabs")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    tabs.append(HoldingTabSettings.new(after: tabs))
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if tabs.isEmpty {
                Text("No tabs. The part is cut free of the stock; add tabs to keep it attached.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                positionDrawing
            }

            ForEach(Array($tabs.enumerated()), id: \.element.id) { index, $tab in
                GroupBox {
                    VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
                        InspectorNumberField(title: "Position",
                                             value: clamped($tab.positionRatio, HoldingTabSettings.positionRange),
                                             suffix: "ratio (0-1)")
                            .help("How far along the contour the tab sits, as a fraction of its total length.")
                        InspectorNote(text: String(format: "%.0f %% of the way along the contour, counted from where it starts. 0 and 1 are the same spot.",
                                                   tab.positionRatio * 100))
                        InspectorNumberField(title: "Width",
                                             value: clamped($tab.width, HoldingTabSettings.widthRange),
                                             suffix: "mm")
                            .help("How long the tab is, measured along the contour.")
                        InspectorNumberField(title: "Height",
                                             value: clamped($tab.height, HoldingTabSettings.heightRange),
                                             suffix: "mm")
                            .help("How much material the tab leaves, measured up from the bottom of the cut. The tool rises to this height over the tab.")
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Text("Tab \(index + 1)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button {
                            let id = tab.id
                            tabs.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove this tab")
                    }
                }
            }
        }
        .padding(16)
    }

    /// Where the tabs sit along the contour, since "position" alone doesn't say it: the selected
    /// shape with a numbered marker per tab. With several shapes, one is shown at a time.
    @ViewBuilder
    private var positionDrawing: some View {
        let outlines = shapes()
        let index = min(shapeIndex, max(outlines.count - 1, 0))

        VStack(alignment: .leading, spacing: 6) {
            if outlines.count > 1 {
                HStack(spacing: 8) {
                    Button {
                        shapeIndex = (index + outlines.count - 1) % outlines.count
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Text("Shape \(index + 1) of \(outlines.count)")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)

                    Button {
                        shapeIndex = (index + 1) % outlines.count
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                }
            }

            TabPositionDiagram(tabs: tabs, shape: outlines.isEmpty ? nil : outlines[index])

            Text(outlines.isEmpty
                 ? "Schematic. Select the contour on the canvas to see its real shape here."
                 : "Approximate: the tool follows the shape offset by its radius, so real positions shift slightly. 0 → 1 runs along the shape from its start.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The ranges are the limits the engine accepts (see `SC.MachiningOperation.formFields`),
    /// so a typed value is pulled back inside them.
    private func clamped(_ value: Binding<Double>, _ range: ClosedRange<Double>) -> Binding<Double> {
        Binding(get: { value.wrappedValue },
                set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) })
    }
}

/// A closed contour with one numbered marker per tab, placed by its position ratio: the
/// selected shape when there is one, otherwise a schematic rounded rectangle. A ratio is a
/// fraction of the outline's length counted from where it starts (the start of its path), so
/// 0.25 is a quarter of the way round, 0.5 halfway. The tool actually follows the shape
/// offset by its radius, and the engine decides the real start and direction, so the markers
/// are an approximation.
private struct TabPositionDiagram: View {
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

#Preview {
    @Previewable @State var tabs = [HoldingTabSettings(positionRatio: 0.25, width: 4, height: 1.5)]
    HoldingTabsEditor(tabs: $tabs)
        .frame(width: 400)
}
