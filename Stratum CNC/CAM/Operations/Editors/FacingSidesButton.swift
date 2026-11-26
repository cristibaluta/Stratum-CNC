//
//  FacingSidesButton.swift
//  Stratum CNC
//
//  The facing's extension, set per side. An icon opens a popover with a title, a one-line
//  explanation and the selected shapes in top view, inside their bounding box. Each side of that
//  box has a text field on its edge: type how far the facing runs past that side (0 by default).
//  The dotted line is the area that will be faced, redrawn as the values change. Under the
//  picture: the original and final area sizes. The icon draws the extended sides in blue.
//  Same pattern as `FeedCalculatorButton` / `HoldingTabsEditor`.
//

import SwiftUI

/// The icon after the Extension row: a dashed square whose extended sides are blue.
struct FacingSidesButton: View {
    @Binding var sides: FacingSides
    /// The selected shapes' outlines in world space; called when the popover is drawn.
    var shapes: () -> [CGPath] = { [] }
    /// What the sides are for: a facing's passes (the default) or a pocket's outline.
    var purpose: Purpose = .facing

    /// The words that change between the facing's and the pocket's extension.
    enum Purpose {
        case facing, pocket

        var title: String {
            self == .facing ? "Facing extension" : "Pocket extension"
        }

        var detail: String {
            self == .facing
                ? "Type how far the facing runs past each side of the selection, in mm."
                : "Type how far the pocket runs out past each side of its box, in mm. Only the wall that reaches that side moves; the rest stays as drawn."
        }

        var fieldHelp: String {
            self == .facing
                ? "how far the facing runs past this side, in mm"
                : "how far the pocket runs out past this side, in mm"
        }
    }

    @State private var isPresented = false

    var body: some View {
        HoverIconButton {
            isPresented = true
        } label: {
            FacingSidesIcon(sides: sides)
                .frame(width: 24, height: 18)
        }
        // Shares the row with other controls: without this the icon is the first thing squeezed out.
        .fixedSize()
        .layoutPriority(1)
        .help("Set how far the \(purpose == .facing ? "facing" : "pocket") extends past each side (\(sides.summary))")
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            FacingSidesEditor(sides: $sides, shapes: shapes, purpose: purpose)
                .frame(width: 380)
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
            edge(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), on: sides.back > 0)
            edge(CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), on: sides.front > 0)
            edge(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), on: sides.left > 0)
            edge(CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), on: sides.right > 0)
        }
    }
}

struct FacingSidesEditor: View {
    @Binding var sides: FacingSides
    var shapes: () -> [CGPath] = { [] }
    var purpose: FacingSidesButton.Purpose = .facing

    var body: some View {
        let outlines = shapes()
        let box = FacingSidesDiagram.selectionBox(of: outlines)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(purpose.title)
                    .font(.headline)
                Text(purpose.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FacingSidesDiagram(sides: $sides, shapes: outlines, fieldHelp: purpose.fieldHelp)
                .frame(height: 230)

            Divider()

            // The numbers behind the dotted line
            VStack(alignment: .leading, spacing: 8) {
                areaRow("Original", box)
                areaRow("Final", box.map { sides.area(of: $0) })
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

/// The selected shapes inside their bounding box, one text field per side on its edge, and the
/// dotted outline of the faced area. Drawn in top view with Y up, like the canvas.
struct FacingSidesDiagram: View {
    @Binding var sides: FacingSides
    /// The selected shapes in world space. Empty draws a schematic shape instead.
    let shapes: [CGPath]
    var fieldHelp = "how far the facing runs past this side, in mm"

    /// The schematic's box, since mm mean nothing without a shape.
    private static let schematicBox = CGRect(x: 0, y: 0, width: 60, height: 40)

    /// Room around the drawing for the fields, which sit on the edges of the widest area.
    private let marginX: CGFloat = 36
    private let marginY: CGFloat = 20

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
            let drawing = CGRect(origin: .zero, size: proxy.size).insetBy(dx: marginX, dy: marginY)
            let hasShapes = !shapes.isEmpty
            let box = Self.selectionBox(of: shapes) ?? Self.schematicBox

            // Fitted to the box with every side extended by the longest one, so the picture
            // doesn't jump about while one side is typed.
            let longest = max(sides.left, sides.right, sides.front, sides.back)
            let widest = FacingSides.all(longest).area(of: box)
            let scale = min(drawing.width / max(widest.width, 0.0001),
                            drawing.height / max(widest.height, 0.0001))
            let fit = Fit(center: CGPoint(x: drawing.midX, y: drawing.midY),
                          worldCenter: CGPoint(x: widest.midX, y: widest.midY),
                          scale: scale)

            let boxView = fit.rect(box)
            let areaView = fit.rect(sides.area(of: box))

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

                // One line and field per side, on the box's edge
                ForEach(FacingSides.Side.allCases) { side in
                    handle(for: side, on: boxView)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityLabel("How far the facing extends past each side")
    }

    /// A thin line on the box's edge, as thick as the dotted contour: accent while the side is
    /// extended, grey when not. A text field with the side's length sits on the middle of the line.
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
        let isOn = sides[side] > 0

        return ZStack {
            Rectangle()
                .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: horizontal ? length : 1.5, height: horizontal ? 1.5 : length)

            // The background keeps the line and the shape from showing through the field.
            SideLengthField(value: Binding(get: { sides[side] },
                                           set: { sides[side] = $0 }))
                .help("\(side.title): \(fieldHelp)")
        }
        .frame(width: horizontal ? length : 56, height: horizontal ? 24 : length)
        .position(center)
    }
}

/// A small centered number field for one side's length, in mm. Anything under 0 becomes 0.
private struct SideLengthField: View {
    @Binding var value: Double

    var body: some View {
        TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 11).monospacedDigit())
            .frame(width: 40)
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
            .background(.background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var sides = FacingSides(left: 3, right: 0, front: 2, back: 1)
    FacingSidesEditor(sides: $sides) {
        [CGPath(ellipseIn: CGRect(x: 10, y: 5, width: 50, height: 30), transform: nil)]
    }
}
