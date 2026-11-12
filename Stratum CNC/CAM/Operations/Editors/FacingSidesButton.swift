//
//  FacingSidesButton.swift
//  Stratum CNC
//
//  The facing's "which sides to extend". An icon after the Extension field opens a popover with
//  a title, a one-line explanation and the selected shapes in top view, inside their bounding
//  box. Each side of that box has a checkbox on its edge: tick it (or click the line) to extend
//  the facing past that side. The dotted line is the area that will be faced, redrawn as the
//  sides and the length change. Under the picture: the original and final area sizes and the
//  Extension field. The icon draws its active sides in blue (none while the extension is 0).
//  Same pattern as `FeedCalculatorButton` / `HoldingTabsEditor`.
//

import SwiftUI

/// The icon after the Extension field: a dashed square whose extended sides are blue. Nothing
/// is blue while the extension is 0, since nothing is extended then.
struct FacingSidesButton: View {
    @Binding var sides: FacingSides
    @Binding var extensionLength: Double
    /// The selected shapes' outlines in world space; called when the popover is drawn.
    var shapes: () -> [CGPath] = { [] }

    @State private var isPresented = false

    var body: some View {
        HoverIconButton {
            isPresented = true
        } label: {
            FacingSidesIcon(sides: extensionLength > 0 ? sides : FacingSides(left: false, right: false,
                                                                            front: false, back: false))
                .frame(width: 24, height: 18)
        }
        // Shares the row with the field: without this the icon is the first thing squeezed out.
        .fixedSize()
        .layoutPriority(1)
        .help(extensionLength > 0
              ? "Choose which sides the facing extends past (\(sides.summary))"
              : "Choose which sides the facing extends past (extension is 0)")
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            FacingSidesEditor(sides: $sides, extensionLength: $extensionLength, shapes: shapes)
                .frame(width: 340)
        }
    }
}

/// A dashed square, each side drawn on its own so the extended ones can be blue.
/// Y is up like the canvas: "back" is the top edge, "front" the bottom one.
struct FacingSidesIcon: View {
    let sides: FacingSides

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) - 2
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                              width: side, height: side)
            let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 2.5])

            func edge(_ from: CGPoint, _ to: CGPoint, on: Bool) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(on ? Color.accentColor : Color.secondary), style: style)
            }
            edge(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), on: sides.back)
            edge(CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), on: sides.front)
            edge(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), on: sides.left)
            edge(CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), on: sides.right)
        }
    }
}

struct FacingSidesEditor: View {
    @Binding var sides: FacingSides
    @Binding var extensionLength: Double
    var shapes: () -> [CGPath] = { [] }

    var body: some View {
        let outlines = shapes()
        let box = FacingSidesDiagram.selectionBox(of: outlines)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Facing extension")
                    .font(.headline)
                Text("Select the sides you want the facing extended past.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FacingSidesDiagram(sides: $sides, extensionLength: extensionLength, shapes: outlines)
                .frame(height: 210)

            Divider()

            // The numbers behind the dotted line
            VStack(alignment: .leading, spacing: 8) {
                areaRow("Original", box)
                areaRow("Final", box.map { sides.area(of: $0, extendedBy: extensionLength) })
                InspectorNumberField(title: "Extension", value: $extensionLength, suffix: "mm")
            }
        }
        .padding(16)
    }

    /// "Original  60.0 × 40.0 mm"; a dash when no shape is selected.
    private func areaRow(_ title: String, _ rect: CGRect?) -> some View {
        InspectorRow(label: title) {
            Text(rect.map { String(format: "%.1f × %.1f mm", Double($0.width), Double($0.height)) } ?? "—")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
    }
}

/// The selected shapes inside their bounding box, one line and checkbox per side, and the dotted
/// outline of the faced area. Drawn in top view with Y up, like the canvas.
struct FacingSidesDiagram: View {
    @Binding var sides: FacingSides
    let extensionLength: Double
    /// The selected shapes in world space. Empty draws a schematic shape instead.
    let shapes: [CGPath]

    /// The schematic's box and how far it shows the extension, since mm mean nothing without a shape.
    private static let schematicBox = CGRect(x: 0, y: 0, width: 60, height: 40)
    private static let schematicExtension: Double = 7

    /// Room around the drawing for the checkboxes, which sit on the edges of the widest area.
    private let margin: CGFloat = 22

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
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)

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

                // One line and checkbox per side, on the box's edge
                ForEach(FacingSides.Side.allCases) { side in
                    handle(for: side, on: boxView)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityLabel("Sides the facing extends past")
    }

    /// A thin line on the box's edge, as thick as the dotted contour: accent while the side is
    /// extended, grey when not. A checkbox sits on the middle of the line. The clickable area is
    /// wider than what is drawn, and clicking the line toggles the side like the checkbox does.
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

        return ZStack {
            Rectangle()
                .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: horizontal ? length : 1.5, height: horizontal ? 1.5 : length)

            // The background keeps the line and the shape from showing through the checkbox.
            Toggle("", isOn: Binding(get: { sides[side] },
                                     set: { sides[side] = $0 }))
                .labelsHidden()
                .stCheckboxToggleStyle()
                .controlSize(.small)
                .padding(2)
                .background(.background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
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
    @Previewable @State var length = 3.0
    FacingSidesEditor(sides: $sides, extensionLength: $length) {
        [CGPath(ellipseIn: CGRect(x: 10, y: 5, width: 50, height: 30), transform: nil)]
    }
}
