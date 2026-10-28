//
//  LeadInOutButton.swift
//  Stratum CNC
//
//  The contour's lead-in and lead-out: a row in the Operation section with a switch, a
//  one-line summary of the settings in use and a gear that opens the popover where they are
//  edited, with a drawing and an explanation of what the move does. Same pattern as
//  `HoldingTabsButton` / `RampingButton`.
//

import SwiftUI
import StratumCAM

// MARK: - Row

/// "Lead-In" / "Lead-Out": the switch, then (while it is on) what it is set to and the gear.
struct LeadInOutRow: View {
    let title: String
    @Binding var leadInOut: LeadInOutSettings?
    /// Orange gear: the settings are on but something about them needs a look (see `LeadInOutEditor`).
    var needsAttention: Bool = false
    let action: () -> Void

    var body: some View {
        InspectorRow(label: title) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { leadInOut != nil },
                                         set: { leadInOut = $0 ? (leadInOut ?? .seed) : nil }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if let current = leadInOut {
                    Text(current.summary)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(current.detailedSummary)

                    Spacer(minLength: 4)

                    Button(action: action) {
                        Image(systemName: needsAttention ? "exclamationmark.triangle.fill" : "gearshape")
                            .foregroundStyle(needsAttention ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("\(title) settings")
                } else {
                    Text("Off")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension LeadInOutSettings {

    /// What the switch seeds when it is turned on: the same 3 mm line at 300 mm/min that the
    /// library's own form (`SC.LeadInOut.optionalFormField`) starts from.
    static let seed = LeadInOutSettings(style: .linear(length: 3), feedRate: 300)

    /// "Line 3 mm · 300 mm/min" or "Arc R3 mm · 90° · 300 mm/min".
    var summary: String {
        "\(styleSummary) · \(Self.format(feedRate)) mm/min"
    }

    var styleSummary: String {
        switch style {
            case .linear(let length):
                return "Line \(Self.format(length)) mm"
            case .arc(let radius, let sweep):
                return "Arc R\(Self.format(radius)) mm · \(Self.format(sweep))°"
        }
    }

    /// The long form, for the tooltip when the summary doesn't fit the row.
    var detailedSummary: String {
        switch style {
            case .linear(let length):
                return "Straight run of \(Self.format(length)) mm, at \(Self.format(feedRate)) mm/min"
            case .arc(let radius, let sweep):
                return "Arc of radius \(Self.format(radius)) mm, sweeping \(Self.format(sweep))°, at \(Self.format(feedRate)) mm/min"
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }
}

// MARK: - Editor

/// The popover behind the gear: what the move is for, a drawing of it that follows the
/// settings, and the fields. Ranges are the limits the library accepts
/// (`SC.LeadInOut.formFields`), so a typed value is pulled back inside them.
struct LeadInOutEditor: View {

    enum Role {
        case leadIn, leadOut

        var title: String {
            self == .leadIn ? "Lead-in" : "Lead-out"
        }

        var explanation: String {
            switch self {
                case .leadIn:
                    return "The tool plunges beside the part, then eases onto the contour along this move while it is already cutting. Plunging straight into the wall, or turning onto it at a corner, leaves a mark where the tool starts."
                case .leadOut:
                    return "At the end of the cut the tool leaves the contour along this move before it lifts. Stopping and lifting right on the finished wall leaves a mark where the tool dwells."
            }
        }
    }

    private enum StyleKind: String, CaseIterable, Identifiable {
        case linear = "Linear", arc = "Arc"
        var id: String { rawValue }
    }

    let role: Role
    @Binding var leadInOut: LeadInOutSettings?
    let side: SC.CutSide
    let toolDiameter: Double

    private var current: LeadInOutSettings {
        leadInOut ?? .seed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(role.title)
                .font(.system(size: 13, weight: .semibold))

            Text(role.explanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LeadInOutDiagram(role: role, style: current.style, side: side, toolDiameter: toolDiameter)

            Text(diagramCaption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: styleKind) {
                ForEach(StyleKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(styleExplanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
                switch current.style {
                    case .linear:
                        InspectorNumberField(title: "Length", value: length, suffix: "mm")
                            .help("How far before the contour the tool plunges, measured along the line the cut starts on.")
                    case .arc:
                        InspectorNumberField(title: "Radius", value: radius, suffix: "mm")
                            .help("Radius of the arc the tool centre follows. The arc must fit in the free space beside the wall.")
                        InspectorNumberField(title: "Sweep", value: sweep, suffix: "°")
                            .help("How much of the circle the tool travels. 90° is a quarter turn.")
                }
                InspectorNumberField(title: "Feed rate", value: feedRate, suffix: "mm/min")
                    .help("Speed of this move. The plunge itself uses the plunge feed.")
            }

            ForEach(notes, id: \.text) { note in
                InspectorNote(text: note.text, isWarning: note.isWarning, isIndented: false)
            }
        }
        .padding(16)
    }

    // MARK: Copy

    private var diagramCaption: String {
        let wall: String
        switch side {
            case .outside:   wall = "cut outside the part"
            case .inside:    wall = "cut inside the shape"
            case .onContour: wall = "following the line directly"
        }
        let moment = role == .leadIn
            ? "The tool goes down at the blue dot, in material that is still uncut, then follows the blue move onto the contour."
            : "After the cut the tool follows the blue move off the contour and comes up at the blue dot."
        return "Top view of a straight wall, \(wall), travelling left to right, to scale. \(moment) The dashed circle is the tool at that spot, the faint one is the tool on the contour."
    }

    private var styleExplanation: String {
        switch current.style {
            case .linear:
                return "A straight run in line with the first (or last) cutting move. Simple, and needs little room."
            case .arc:
                return "A curved move that joins the wall tangentially, so the tool never meets it head-on. Gives the cleanest surface; needs about the radius of free space beside the wall."
        }
    }

    private struct Note {
        let text: String
        let isWarning: Bool
    }

    private var notes: [Note] {
        var result: [Note] = []
        if case .arc = current.style, side == .onContour {
            result.append(Note(text: "An arc can't be built when the tool follows the contour directly (there is no side for it to swing out to). Use a linear move, or cut inside or outside.",
                               isWarning: true))
        }
        if case .linear = current.style, side == .inside {
            result.append(Note(text: "On a curved inside wall (a round hole, a rounded pocket) a straight run leaves the curve and cuts into the wall; the longer it is, the deeper. Prefer an arc there, or keep the run short.",
                               isWarning: false))
        }
        if role == .leadIn {
            result.append(Note(text: "A lead-in can't be combined with a ramp or helix entry. It repeats at every depth pass.",
                               isWarning: false))
        } else {
            result.append(Note(text: "The lead-out works with every entry. It repeats at every depth pass.",
                               isWarning: false))
        }
        return result
    }

    // MARK: Bindings

    private var styleKind: Binding<StyleKind> {
        Binding(
            get: {
                if case .arc = current.style { return .arc }
                return .linear
            },
            set: { kind in
                switch kind {
                    case .linear: leadInOut?.style = .linear(length: 3)
                    case .arc:    leadInOut?.style = .arc(radius: 3, sweepAngleDegrees: 90)
                }
            }
        )
    }

    private var length: Binding<Double> {
        Binding(
            get: {
                if case .linear(let length) = current.style { return length }
                return 3
            },
            set: { leadInOut?.style = .linear(length: Self.clamp($0, 0.1...20)) }
        )
    }

    private var radius: Binding<Double> {
        Binding(
            get: {
                if case .arc(let radius, _) = current.style { return radius }
                return 3
            },
            set: { newValue in
                if case .arc(_, let sweep) = current.style {
                    leadInOut?.style = .arc(radius: Self.clamp(newValue, 0.1...20), sweepAngleDegrees: sweep)
                }
            }
        )
    }

    private var sweep: Binding<Double> {
        Binding(
            get: {
                if case .arc(_, let sweep) = current.style { return sweep }
                return 90
            },
            set: { newValue in
                if case .arc(let radius, _) = current.style {
                    leadInOut?.style = .arc(radius: radius, sweepAngleDegrees: Self.clamp(newValue, 1...180))
                }
            }
        )
    }

    private var feedRate: Binding<Double> {
        Binding(
            get: { current.feedRate },
            set: { leadInOut?.feedRate = Self.clamp($0, 50...3000) }
        )
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Drawing

/// A straight wall seen from above, with the tool path along it and the lead move drawn the
/// way the library builds it (`SCEngine.resolveLeadIn` / `resolveLeadOut`): a line is the
/// tangent extension of the cut, an arc is tangent to the cut with its centre on the free
/// side, away from the material. Everything is to scale (mm), so the drawing follows the
/// length, radius and sweep, and the tool circle shows how big the move is next to the bit.
struct LeadInOutDiagram: View {
    let role: LeadInOutEditor.Role
    let style: LeadInOutSettings.Style
    let side: SC.CutSide
    /// mm. Zero (no tool picked yet) draws a 6 mm tool.
    let toolDiameter: Double

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: 190)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemFill)))
        .accessibilityLabel("\(role.title) drawing")
    }

    // MARK: Geometry (world space, mm, y up, the wall on y = 0)

    private struct Scene {
        var path: [CGPoint]        // the cut itself
        var lead: [CGPoint]        // the lead move, in the direction of travel
        var toolAtLead: CGPoint    // where the tool is when the lead move begins (in) / ends (out)
        var toolOnContour: CGPoint // where the lead meets the cut
        var toolRadius: Double
        var free: Double           // +1: the waste is above the wall on screen, -1: below
        var isInvalid: Bool        // an arc with no side to swing out to
    }

    private func makeScene() -> Scene {
        let toolRadius = (toolDiameter > 0 ? toolDiameter : 6) / 2
        // +1: the free space is above the wall (outside cut), -1: below it (inside cut).
        let free: Double = side == .inside ? -1 : 1
        let pathY = side == .onContour ? 0 : free * toolRadius
        let contourPoint = CGPoint(x: 0, y: pathY)

        var lead: [CGPoint] = []
        var invalid = false
        var extent = 0.0

        switch style {
            case .linear(let length):
                extent = length
                lead = role == .leadIn
                    ? [CGPoint(x: -length, y: pathY), contourPoint]
                    : [contourPoint, CGPoint(x: length, y: pathY)]

            case .arc(let radius, let sweepDegrees):
                extent = radius
                if side == .onContour {
                    // Zero offset: the library has no centre for the arc. See `ToolpathData.leadArcOnContour`.
                    invalid = true
                } else {
                    let center = CGPoint(x: 0, y: pathY + free * radius)
                    let atContour = -free * Double.pi / 2          // straight "down" to the wall, or "up"
                    let turn = free > 0 ? 1.0 : -1.0                // travelling +x: CCW above the wall, CW below
                    let sweep = sweepDegrees * Double.pi / 180
                    let steps = 32
                    for i in 0...steps {
                        let f = Double(i) / Double(steps)
                        let angle = role == .leadIn
                            ? atContour - turn * sweep * (1 - f)
                            : atContour + turn * sweep * f
                        lead.append(CGPoint(x: center.x + radius * cos(angle),
                                            y: center.y + radius * sin(angle)))
                    }
                }
        }

        // The straight cut either side of the contour point, long enough to read as a wall.
        let span = max(6, extent * 0.9, toolRadius * 3)
        let path = role == .leadIn
            ? [contourPoint, CGPoint(x: span, y: pathY)]
            : [CGPoint(x: -span, y: pathY), contourPoint]

        let toolAtLead = role == .leadIn ? (lead.first ?? contourPoint) : (lead.last ?? contourPoint)

        return Scene(path: path, lead: lead, toolAtLead: toolAtLead, toolOnContour: contourPoint,
                     toolRadius: toolRadius, free: free, isInvalid: invalid)
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let scene = makeScene()

        // What has to be on screen, to fit it: the cut, the lead, the tool at the plunge and a
        // little room above/below it for the label.
        var points = scene.path + scene.lead
        let r = CGFloat(scene.toolRadius)
        points += [CGPoint(x: scene.toolAtLead.x - r, y: scene.toolAtLead.y - r),
                   CGPoint(x: scene.toolAtLead.x + r, y: scene.toolAtLead.y + r),
                   CGPoint(x: 0, y: 0)]
        let top: CGFloat = (points.map(\.y).max() ?? 0) + (scene.free > 0 ? r * 0.6 : r * 0.2)
        let bottom: CGFloat = (points.map(\.y).min() ?? 0) - (scene.free > 0 ? r * 0.2 : r * 0.6)
        let left: CGFloat = points.map(\.x).min() ?? 0
        let right: CGFloat = points.map(\.x).max() ?? 1

        let padding: CGFloat = 22
        let width: CGFloat = max(right - left, 0.001)
        let height: CGFloat = max(top - bottom, 0.001)
        let scale: CGFloat = min((size.width - 2 * padding) / width,
                                 (size.height - 2 * padding) / height)
        let originX: CGFloat = (size.width - width * scale) / 2 - left * scale
        let originY: CGFloat = (size.height - height * scale) / 2 + top * scale

        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: originX + point.x * scale, y: originY - point.y * scale)
        }

        func polyline(_ pts: [CGPoint]) -> Path {
            var path = Path()
            for (index, point) in pts.enumerated() {
                if index == 0 {
                    path.move(to: map(point))
                } else {
                    path.addLine(to: map(point))
                }
            }
            return path
        }

        func circle(at center: CGPoint, radius: CGFloat) -> Path {
            let c = map(center)
            let rr = radius * scale
            return Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr))
        }

        let accent = Color.accentColor
        let wallY = map(CGPoint(x: 0, y: 0)).y
        let full = CGRect(origin: .zero, size: size)

        // Top view: the part (stays) on one side of the wall, the material to remove on the
        // other, hatched because it is still uncut. The plunge goes into that hatched side.
        let wasteRect = scene.free > 0
            ? CGRect(x: 0, y: 0, width: size.width, height: max(wallY, 0))
            : CGRect(x: 0, y: wallY, width: size.width, height: max(size.height - wallY, 0))
        let partRect = scene.free > 0
            ? CGRect(x: 0, y: wallY, width: size.width, height: max(size.height - wallY, 0))
            : CGRect(x: 0, y: 0, width: size.width, height: max(wallY, 0))

        context.fill(Path(partRect), with: .color(Color.secondary.opacity(0.30)))
        context.fill(Path(wasteRect), with: .color(Color.orange.opacity(0.07)))
        do {
            var hatch = context
            hatch.clip(to: Path(wasteRect))
            var lines = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 9
            }
            hatch.stroke(lines, with: .color(Color.orange.opacity(0.22)), style: StrokeStyle(lineWidth: 1))
        }
        context.stroke(Path { $0.move(to: CGPoint(x: 0, y: wallY)); $0.addLine(to: CGPoint(x: size.width, y: wallY)) },
                       with: .color(Color.primary.opacity(0.8)), style: StrokeStyle(lineWidth: 2))

        let partLabelY = scene.free > 0 ? min(wallY + 14, size.height - 8) : max(wallY - 14, 8)
        let wasteLabelY = scene.free > 0 ? 10 : size.height - 10
        context.draw(Text(side == .onContour ? "One side" : "Part (stays)")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(Color.secondary),
                     at: CGPoint(x: 8, y: partLabelY), anchor: .leading)
        context.draw(Text("Material to remove")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(Color.orange),
                     at: CGPoint(x: 8, y: wasteLabelY), anchor: .leading)
        context.draw(Text("TOP VIEW").font(.system(size: 9, weight: .semibold)).foregroundColor(Color.secondary),
                     at: CGPoint(x: size.width - 8, y: scene.free > 0 ? 10 : size.height - 10), anchor: .trailing)

        // The tool seen from above: faint on the contour, dashed where the lead move begins (in)
        // or ends (out).
        context.fill(circle(at: scene.toolOnContour, radius: r), with: .color(accent.opacity(0.10)))
        context.stroke(circle(at: scene.toolOnContour, radius: r),
                       with: .color(accent.opacity(0.35)), style: StrokeStyle(lineWidth: 1))
        if !scene.lead.isEmpty {
            context.fill(circle(at: scene.toolAtLead, radius: r), with: .color(Color(.windowBackgroundColor).opacity(0.6)))
            context.stroke(circle(at: scene.toolAtLead, radius: r),
                           with: .color(accent), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
        }

        // The cut (tool centre), then the lead move over it.
        context.stroke(polyline(scene.path),
                       with: .color(Color.primary.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        if scene.isInvalid {
            context.draw(Text("An arc needs a side to swing out to")
                            .font(.system(size: 11, weight: .medium)).foregroundColor(Color.orange),
                         at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
        } else {
            context.stroke(polyline(scene.lead),
                           with: .color(accent),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            arrowHead(&context, along: scene.lead.map(map), color: accent)

            // The point where the tool goes down (in) or comes up (out), at the centre of the dashed tool.
            let marker = map(scene.toolAtLead)
            context.fill(Path(ellipseIn: CGRect(x: marker.x - 4.5, y: marker.y - 4.5, width: 9, height: 9)),
                         with: .color(accent))
            context.stroke(Path(ellipseIn: CGRect(x: marker.x - 4.5, y: marker.y - 4.5, width: 9, height: 9)),
                           with: .color(Color(.windowBackgroundColor)), style: StrokeStyle(lineWidth: 1.5))
            let isIn = role == .leadIn
            let labelAbove = scene.free > 0
            let labelY = labelAbove ? marker.y - r * scale - 6 : marker.y + r * scale + 6
            context.draw(Text(isIn ? "● Plunge here (tool goes down)" : "● Lift here (tool comes up)")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(accent),
                         at: CGPoint(x: min(max(marker.x, 90), size.width - 90), y: min(max(labelY, 8), size.height - 8)),
                         anchor: labelAbove ? .bottom : .top)
        }

        // Which way the tool travels along the wall.
        context.draw(Text("cut direction →").font(.system(size: 9)).foregroundColor(Color.secondary),
                     at: CGPoint(x: size.width - 8, y: scene.free > 0 ? size.height - 8 : 22), anchor: .trailing)
        _ = full
    }

    /// A small arrowhead at the end of the polyline, along its last stretch.
    private func arrowHead(_ context: inout GraphicsContext, along points: [CGPoint], color: Color) {
        guard points.count >= 2 else {
            return
        }
        let end = points[points.count - 1]
        // Look back far enough that a short last segment of an arc still gives a direction.
        let back = points[max(points.count - 3, 0)]
        let angle = atan2(end.y - back.y, end.x - back.x)
        let size: CGFloat = 7
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - size * cos(angle - .pi / 6), y: end.y - size * sin(angle - .pi / 6)))
        head.addLine(to: CGPoint(x: end.x - size * cos(angle + .pi / 6), y: end.y - size * sin(angle + .pi / 6)))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}

#Preview {
    @Previewable @State var leadIn: LeadInOutSettings? = LeadInOutSettings(style: .arc(radius: 4, sweepAngleDegrees: 90), feedRate: 300)
    LeadInOutEditor(role: .leadIn, leadInOut: $leadIn, side: .outside, toolDiameter: 3)
        .frame(width: 400)
}
