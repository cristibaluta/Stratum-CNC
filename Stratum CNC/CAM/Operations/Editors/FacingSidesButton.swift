//
//  FacingSidesButton.swift
//  Stratum CNC
//
//  The facing's "which sides to extend". An icon after the Extension field opens a popover with
//  the selected shapes in top view, inside their bounding box, and one handle on each side of
//  that box: click a handle (or its chip below) to stop the extension on that side. The dotted
//  line is the area that will be faced, redrawn as the sides and the length change.
//  Same pattern as `FeedCalculatorButton` / `HoldingTabsEditor`.
//

import SwiftUI

/// The icon after the Extension field. Accent-coloured while some side is switched off.
struct FacingSidesButton: View {
    @Binding var sides: FacingSides
    let extensionLength: Double
    /// The selected shapes' outlines in world space; called when the popover is drawn.
    var shapes: () -> [CGPath] = { [] }

    @State private var isPresented = false

    var body: some View {
        HoverIconButton {
            isPresented = true
        } label: {
            Image(systemName: sides.isAll ? "square.dashed" : "square.dashed.inset.filled")
                .font(.system(size: 16))
                .foregroundStyle(sides.isAll ? Color.secondary : Color.accentColor)
                .frame(width: 24)
        }
        // Shares the row with the field: without this the icon is the first thing squeezed out.
        .fixedSize()
        .layoutPriority(1)
        .help("Choose which sides the facing extends past (\(sides.summary))")
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            FacingSidesEditor(sides: $sides, extensionLength: extensionLength, shapes: shapes)
                .frame(width: 340)
        }
    }
}

struct FacingSidesEditor: View {
    @Binding var sides: FacingSides
    let extensionLength: Double
    var shapes: () -> [CGPath] = { [] }

    var body: some View {
        let outlines = shapes()
        let box = FacingSidesDiagram.selectionBox(of: outlines)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Extend facing")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("All") { sides = .all }
                    .disabled(sides.isAll)
                Button("None") { sides = FacingSides(left: false, right: false, front: false, back: false) }
                    .disabled(sides.isNone)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            FacingSidesDiagram(sides: $sides, extensionLength: extensionLength, shapes: outlines)
                .frame(height: 220)

            HStack(spacing: 6) {
                ForEach(FacingSides.Side.allCases) { side in
                    Toggle(side.title, isOn: Binding(get: { sides[side] },
                                                     set: { sides[side] = $0 }))
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                }
            }

            Text(sizeSummary(of: box))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(note(hasShapes: !outlines.isEmpty))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    /// "Selection 60.0 × 40.0 mm → faced 62.0 × 41.0 mm", the numbers behind the dotted line.
    private func sizeSummary(of box: CGRect?) -> String {
        guard let box else {
            return sides.isNone || extensionLength == 0
                ? "Nothing is added past the selection."
                : "Extends \(String(format: "%.2f", extensionLength)) mm on: \(sides.summary)."
        }
        let area = sides.area(of: box, extendedBy: extensionLength)
        return String(format: "Selection %.1f × %.1f mm → faced area %.1f × %.1f mm",
                      Double(box.width), Double(box.height), Double(area.width), Double(area.height))
    }

    private func note(hasShapes: Bool) -> String {
        var text = "The facing covers the bounding box of the selected shapes. The dotted line is the area that will be faced: "
            + "a side that is switched off stops at the box's edge instead of running \(String(format: "%.2f", extensionLength)) mm past it."
        if !hasShapes {
            text += " Schematic: select shapes on the canvas to see their real shape here."
        }
        return text
    }
}

/// The selected shapes inside their bounding box, one handle per side, and the dotted outline of
/// the faced area. Drawn in top view with Y up, like the canvas.
struct FacingSidesDiagram: View {
    @Binding var sides: FacingSides
    let extensionLength: Double
    /// The selected shapes in world space. Empty draws a schematic shape instead.
    let shapes: [CGPath]

    /// The schematic's box and how far it shows the extension, since mm mean nothing without a shape.
    private static let schematicBox = CGRect(x: 0, y: 0, width: 60, height: 40)
    private static let schematicExtension: Double = 7

    private let margin: CGFloat = 34

    /// The box around all the shapes, `nil` when there are none.
    static func selectionBox(of shapes: [CGPath]) -> CGRect? {
        let boxes = shapes.map { $0.boundingBoxOfPath }.filter { !$0.isNull && !$0.isInfinite }
        guard let first = boxes.first else {
            return nil
        }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    /// World → view: centred, scaled to fit and flipped (the shapes' Y points up, the screen's down).
    private struct Fit {
        let center: CGPoint      // of the drawing, in view space
        let worldCenter: CGPoint
        let scale: CGFloat

        var transform: CGAffineTransform {
            CGAffineTransform.identity
                .translatedBy(x: center.x, y: center.y)
                .scaledBy(x: scale, y: -scale)
                .translatedBy(x: -worldCenter.x, y: -worldCenter.y)
        }

        func rect(_ world: CGRect) -> CGRect {
            world.applying(transform)   // a flip keeps a rectangle a rectangle; CGRect normalises it
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let drawing = CGRect(origin: .zero, size: proxy.size).insetBy(dx: margin, dy: margin)
            let hasShapes = !shapes.isEmpty
            let box = Self.selectionBox(of: shapes) ?? Self.schematicBox
            let length = hasShapes ? extensionLength : Self.schematicExtension

            // Fitted to the box with every side extended, so the picture doesn't jump about
            // while sides are switched on and off.
            let widest = FacingSides.all.area(of: box, extendedBy: length)
            let scale = min(drawing.width / max(widest.width, 0.0001),
                            drawing.height / max(widest.height, 0.0001))
            let fit = Fit(center: CGPoint(x: drawing.midX, y: drawing.midY),
                          worldCenter: CGPoint(x: widest.midX, y: widest.midY),
                          scale: scale)

            let boxView = fit.rect(box)
            let areaView = fit.rect(sides.area(of: box, extendedBy: length))

            ZStack {
                // What will be faced
                Rectangle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: areaView.width, height: areaView.height)
                    .position(x: areaView.midX, y: areaView.midY)
                Path(areaView)
                    .stroke(Color.accentColor,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))

                // The selection's bounding box, the edge the sides are measured from
                Path(boxView)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)

                // The shapes
                if hasShapes {
                    ForEach(shapes.indices, id: \.self) { index in
                        let path = Path(shapes[index]).applying(fit.transform)
                        path.fill(Color.secondary.opacity(0.12))
                        path.stroke(Color.primary.opacity(0.75),
                                    style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    }
                } else {
                    let path = Path(roundedRect: boxView, cornerRadius: 10)
                    path.fill(Color.secondary.opacity(0.12))
                    path.stroke(Color.primary.opacity(0.75), lineWidth: 1.5)
                }

                // One handle per side, on the box's edge
                ForEach(FacingSides.Side.allCases) { side in
                    handle(for: side, on: boxView)
                }

                // Which way is which
                edgeLabel("Back").position(x: proxy.size.width / 2, y: 10)
                edgeLabel("Front").position(x: proxy.size.width / 2, y: proxy.size.height - 10)
                edgeLabel("Left").position(x: 18, y: proxy.size.height / 2)
                edgeLabel("Right").position(x: proxy.size.width - 20, y: proxy.size.height / 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityLabel("Sides the facing extends past")
    }

    private func edgeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
    }

    /// A thick segment on the box's edge: accent while the side is extended, grey when not.
    /// The clickable area is wider than what is drawn.
    private func handle(for side: FacingSides.Side, on box: CGRect) -> some View {
        let horizontal = side == .front || side == .back
        let minLength: CGFloat = 24
        let length = max(horizontal ? box.width : box.height, minLength)
        let center: CGPoint
        switch side {
            case .left:  center = CGPoint(x: box.minX, y: box.midY)
            case .right: center = CGPoint(x: box.maxX, y: box.midY)
            case .back:  center = CGPoint(x: box.midX, y: box.minY)   // high Y is up the screen
            case .front: center = CGPoint(x: box.midX, y: box.maxY)
        }
        let isOn = sides[side]

        return Capsule()
            .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.35))
            .frame(width: horizontal ? length : 5, height: horizontal ? 5 : length)
            .frame(width: horizontal ? length : 24, height: horizontal ? 24 : length)
            .contentShape(Rectangle())
            .onTapGesture {
                sides[side].toggle()
            }
            .position(center)
            .help("\(side.title): \(isOn ? "extended, click to stop at the selection" : "not extended, click to extend")")
    }
}

#Preview {
    @Previewable @State var sides = FacingSides(left: true, right: false, front: true, back: true)
    FacingSidesEditor(sides: $sides, extensionLength: 3) {
        [CGPath(ellipseIn: CGRect(x: 10, y: 5, width: 50, height: 30), transform: nil)]
    }
}
