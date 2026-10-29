//
//  DirectionGlyph.swift
//  Stratum CNC
//
//  Custom drawing, moved out of DirectionPicker.swift.
//

import SwiftUI

/// A small chip-formation diagram, the way CAM packages draw climb and conventional milling.
///
/// The material is the strip along the bottom, seen from above the tool. Behind the tool the
/// wall is already at its finished position; ahead of it a thin layer of stock is still to be
/// cut. The spindle turns clockwise, and the tooth takes off a crescent-shaped chip (orange):
///
/// - Climb: the tool travels the way its teeth are going at the cut's end, so each tooth
///   bites at the uncut surface with its thickest chip and leaves at the finished wall with none.
/// - Conventional: the tool travels against that, so each tooth starts at the finished wall
///   with no chip and leaves through the uncut surface with its thickest.
///
/// The picture is drawn with the material on top and then turned half a circle, so on screen
/// the material is at the bottom, the teeth at the cut move to the left (clockwise spindle),
/// climb travels to the right and conventional to the left.
/// Drawn in a fixed 60x40 design space and scaled to whatever frame it's given.
struct DirectionGlyph: View {
    let direction: CutDirectionOption
    var tint: Color = .primary

    private let designSize = CGSize(width: 60, height: 40)

    /// +1 when the tool travels to the right, -1 to the left.
    private var travel: CGFloat {
        direction == .conventional ? 1 : -1
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / designSize.width, size.height / designSize.height)
            context.translateBy(x: (size.width - designSize.width * scale) / 2,
                                y: (size.height - designSize.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            // Everything below is drawn with the material along the top; turn it half a circle
            // so the material ends up at the bottom (the spin stays clockwise, the travel flips).
            context.translateBy(x: designSize.width / 2, y: designSize.height / 2)
            context.rotate(by: .degrees(180))
            context.translateBy(x: -designSize.width / 2, y: -designSize.height / 2)

            let line = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            let arrowLine = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
            let width = designSize.width

            // Tool and cut, in design units.
            let radius: CGFloat = 12
            let finishedY: CGFloat = 6                  // the wall the tool leaves
            let center = CGPoint(x: width / 2, y: finishedY + radius)
            let engagement = radius                     // stock it takes off, radially: as deep as the tool is wide from its centre
            let uncutY = finishedY + engagement         // the wall as it was
            let reach = (radius * radius - (radius - engagement) * (radius - engagement)).squareRoot()
            let feedPerTooth: CGFloat = 6             // exaggerated, so the chip is visible

            // Material above the finished wall.
            context.fill(Path(roundedRect: CGRect(x: 1, y: 0, width: width - 2, height: finishedY),
                              cornerRadius: 1),
                         with: .color(Color.secondary.opacity(0.25)))

            // The stock still to cut, ahead of the tool: the whole layer from the tool's top out to
            // the far edge, with the tool's circle cut out of it, so it meets the tool without
            // a gap. (The chip covers what is left inside the circle.)
            let aheadStart = center.x + travel * reach
            let aheadEnd = travel > 0 ? width - 1 : 1
            context.drawLayer { layer in
                layer.fill(Path(CGRect(x: min(center.x, aheadEnd), y: finishedY,
                                       width: abs(aheadEnd - center.x), height: engagement)),
                           with: .color(Color.secondary.opacity(0.14)))
                layer.blendMode = .destinationOut
                layer.fill(circle(at: center, radius: radius), with: .color(.black))
            }

            // The wall: finished behind the tool, uncut ahead of it.
            var wall = Path()
            let behindEnd = travel > 0 ? 1 : width - 1
            wall.move(to: CGPoint(x: behindEnd, y: finishedY))
            wall.addLine(to: CGPoint(x: center.x, y: finishedY))
            wall.move(to: CGPoint(x: aheadStart, y: uncutY))
            wall.addLine(to: CGPoint(x: aheadEnd, y: uncutY))
            context.stroke(wall, with: .color(Color.secondary), style: line)

            // The chip: what this tooth removes, i.e. the tool's circle minus where the previous
            // tooth already was (the circle one feed behind), limited to the stock. It is
            // thickest at the uncut wall, ahead of the tool, and runs out at the finished wall.
            let previous = CGPoint(x: center.x - travel * feedPerTooth, y: center.y)
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: 0, width: width, height: uncutY)))
                layer.fill(circle(at: center, radius: radius), with: .color(Color.orange.opacity(1)))
                layer.blendMode = .destinationOut
                layer.fill(circle(at: previous, radius: radius), with: .color(.black))
            }

            // The tool, with its centre marked.
            context.stroke(circle(at: center, radius: radius), with: .color(tint), style: line)
            context.fill(circle(at: center, radius: 1), with: .color(tint))

            // Spindle rotation: a clockwise arc inside the tool.
            // Its head stops just short of where the tooth starts cutting: at the uncut wall for
            // climb, at the finished wall (where the chip is still nothing) for conventional.
            let entryAngle: CGFloat = direction == .climb
                ? .pi
                : -.pi / 2 - asin(feedPerTooth / (2 * radius))
            let endAngle: CGFloat = entryAngle - (direction == .climb ? 0.4 : 0)
            context.stroke(spinArrow(center: center, radius: radius * 0.35, endAngle: endAngle),
                           with: .color(tint),
                           style: arrowLine)

            // Travel of the tool.
            context.stroke(travelArrow(y: 36.5), with: .color(tint), style: arrowLine)
        }
    }

    private func circle(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius,
                               y: center.y - radius,
                               width: radius * 2,
                               height: radius * 2))
    }

    /// Roughly three-quarters of a circle running clockwise (angles grow clockwise in a
    /// y-down space) and ending, with a small arrowhead, at `endAngle`.
    private func spinArrow(center: CGPoint, radius: CGFloat, endAngle end: CGFloat) -> Path {
        let start: CGFloat = end - 1.45 * .pi
        let steps = 20

        var path = Path()
        for i in 0...steps {
            let angle = start + (end - start) * CGFloat(i) / CGFloat(steps)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        let tip = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
        let heading = end + .pi / 2
        let back: CGFloat = 2
        let span: CGFloat = 1.4
        let base = CGPoint(x: tip.x - back * cos(heading), y: tip.y - back * sin(heading))
        let normal = heading + .pi / 2
        path.move(to: CGPoint(x: base.x + span * cos(normal), y: base.y + span * sin(normal)))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: base.x - span * cos(normal), y: base.y - span * sin(normal)))
        return path
    }

    /// A horizontal arrow showing which way the tool travels.
    private func travelArrow(y: CGFloat) -> Path {
        let left: CGFloat = 14
        let right: CGFloat = designSize.width - 14
        let tail = travel > 0 ? left : right
        let tip = travel > 0 ? right : left

        var path = Path()
        path.move(to: CGPoint(x: tail, y: y))
        path.addLine(to: CGPoint(x: tip, y: y))
        path.move(to: CGPoint(x: tip - travel * 2.8, y: y - 2.2))
        path.addLine(to: CGPoint(x: tip, y: y))
        path.addLine(to: CGPoint(x: tip - travel * 2.8, y: y + 2.2))
        return path
    }
}

#Preview {
    HStack(spacing: 12) {
        DirectionGlyph(direction: .climb).frame(width: 120, height: 80)
        DirectionGlyph(direction: .conventional).frame(width: 120, height: 80)
        DirectionGlyph(direction: .climb).frame(width: 22, height: 15)
    }
    .padding()
}
