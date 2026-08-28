//
// RampingEditor.swift
// Stratum CNC
//
// Created by Cristian Baluta on 24.08.2026.
//
// Assumes, unchanged, elsewhere in the project:
//   enum RampType: String, CaseIterable { case none, linear, helix, zigZag }
//   struct RampingSettings { var enabled: Bool; var type: RampType; var angle: Double; var length: Double }
//   For linear ramps, `length` is maintained as a derived value from angle + stepdown.
//
// NOTE: `linearReturnMode` and `helixDirection` below are kept as local @State
// in RampingEditor because they aren't part of RampingSettings yet. For these
// choices to persist, add to your model:
//   var linearReturnMode: LinearRampReturnMode = .retrace
//   var helixDirection: HelixDirection = .outsideIn
// ...then bind $ramping.linearReturnMode / $ramping.helixDirection instead.

import SwiftUI

// MARK: - Cross-platform colors

private extension Color {
    /// A subtle card/panel background that works on both iOS and macOS.
    static var rampCardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

// MARK: - Extra ramp options

/// How a linear ramp finishes before the main toolpath continues.
enum LinearRampReturnMode: String, CaseIterable, Identifiable {
    case advance = "Continue forward"
    case retrace = "Return to start"
    var id: String { rawValue }
}

/// Spiral direction for a helix ramp.
enum HelixDirection: String, CaseIterable, Identifiable {
    case outsideIn = "Outside → in"
    case insideOut = "Inside → out"
    var id: String { rawValue }
}

// MARK: - Shared math

/// Centralised, best-effort geometry so the small preview cards, the large
/// detail view and the caption text all agree on the same numbers.
enum RampMath {
    static func clampedAngle(_ angle: Double, min minValue: Double = 1, max maxValue: Double = 89) -> Double {
        min(max(angle, minValue), maxValue)
    }

    /// Vertical depth reached over the horizontal ramp `length`, for a given `angle`.
    static func linearDepth(angle: Double, length: Double) -> Double {
        let a = clampedAngle(angle)
        let l = max(length, 0.1)
        return l * tan(a * .pi / 180)
    }

    /// Rough number of helix turns needed to plunge — steeper angle, fewer turns.
    static func helixTurns(angle: Double) -> Int {
        let a = clampedAngle(angle, min: 2, max: 90)
        return min(max(Int((90 / a).rounded()), 1), 8)
    }

    /// Rough number of zig-zag passes across a nominal channel, driven by angle and length.
    static func zigZagPasses(angle: Double, length: Double, channelHeight: Double = 40) -> Int {
        let a = clampedAngle(angle, min: 5, max: 85)
        let l = max(length, 0.1)
        let toothRun = channelHeight / tan(a * .pi / 180)
        return min(max(Int((l / max(toothRun, 4)).rounded(.up)), 1), 10)
    }

    /// Horizontal ramp length required to reach `stepdown` at a given `angle`.
    /// This is the real driving relationship: stepdown is the constraint,
    /// angle sets the slope, and this is how much length that slope needs.
    static func linearRequiredLength(angle: Double, stepdown: Double) -> Double {
        let a = clampedAngle(angle)
        let d = max(stepdown, 0.01)
        return d / tan(a * .pi / 180)
    }

    /// The actual outcome of a linear ramp given angle, available length, and
    /// the stepdown it must never exceed.
    /// - If `length` is enough, the ramp reaches full `stepdown` depth using
    ///   only the portion of `length` it needs (`usedLength <= length`).
    /// - If `length` falls short, the ramp uses all of it but only reaches a
    ///   partial depth — `reachesStepdown` is false, which callers should
    ///   surface as a warning rather than silently under-cutting.
    static func linearRampOutcome(angle: Double, length: Double, stepdown: Double) -> (usedLength: Double, depth: Double, reachesStepdown: Bool) {
        let a = clampedAngle(angle)
        let l = max(length, 0.1)
        let d = max(stepdown, 0.01)
        let requiredLength = d / tan(a * .pi / 180)
        if l >= requiredLength {
            return (requiredLength, d, true)
        } else {
            let depth = l * tan(a * .pi / 180)
            return (l, depth, false)
        }
    }
}

// MARK: - Path-following helper (drives the animated tool dot)

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

private extension CGVector {
    var normalized: CGVector {
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return .zero }
        return CGVector(dx: dx / len, dy: dy / len)
    }
}

/// Returns the point on a polyline at normalised `phase` (0...1), looping.
private func point(along points: [CGPoint], phase: CGFloat) -> CGPoint {
    guard points.count > 1 else { return points.first ?? .zero }
    let segmentLengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
    let total = segmentLengths.reduce(0, +)
    guard total > 0 else { return points[0] }
    var target = phase.truncatingRemainder(dividingBy: 1) * total
    for (index, segmentLength) in segmentLengths.enumerated() {
        if target <= segmentLength {
            let t = segmentLength > 0 ? target / segmentLength : 0
            let p0 = points[index]
            let p1 = points[index + 1]
            return CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t)
        }
        target -= segmentLength
    }
    return points.last!
}

private func phase(for date: Date, cycleDuration: Double) -> CGFloat {
    let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)
    return CGFloat(t / cycleDuration)
}

/// Small triangular arrow indicating direction of travel, tip at `point`.
private func arrowhead(at point: CGPoint, direction: CGVector, length: CGFloat = 7, width: CGFloat = 5) -> Path {
    let normalized = direction.normalized
    let backX = point.x - normalized.dx * length
    let backY = point.y - normalized.dy * length
    let perpX = -normalized.dy * (width / 2)
    let perpY = normalized.dx * (width / 2)
    var path = Path()
    path.move(to: point)
    path.addLine(to: CGPoint(x: backX + perpX, y: backY + perpY))
    path.addLine(to: CGPoint(x: backX - perpX, y: backY - perpY))
    path.closeSubpath()
    return path
}

// MARK: - Layout constants

enum RampGeometry {
    static let previewSize: CGFloat = 108
    static let detailSize: CGFloat = 320
}

// MARK: - Visualization mode

enum RampVisualizationMode {
    case topPreview
    case profileDetail
}

// MARK: - Visualization dispatcher

struct RampVisualization: View {
    let type: RampType
    let angle: Double
    let length: Double
    var stepdown: Double = 1
    var mode: RampVisualizationMode
    var linearReturnMode: LinearRampReturnMode = .retrace
    var helixDirection: HelixDirection = .outsideIn

    var body: some View {
        switch type {
        case .linear:
            switch mode {
            case .topPreview:
                LinearRampTopView(
                    angle: angle,
                    length: length,
                    stepdown: stepdown
                )
            case .profileDetail:
                LinearRampProfileView(
                    angle: angle,
                    length: length,
                    stepdown: stepdown,
                    returnMode: linearReturnMode
                )
            }
        case .helix:
            HelixTopView(
                angle: angle,
                length: length,
                direction: helixDirection
            )
        case .zigZag:
            ZigZagTopView(
                angle: angle,
                length: length
            )
        case .none:
            Color.clear
        }
    }
}


// MARK: - Tappable type selector (replaces the Picker)

struct RampTypeSelector: View {
    @Binding var type: RampType
    var angle: Double
    var length: Double
    var stepdown: Double = 1
    var linearReturnMode: LinearRampReturnMode = .retrace
    var helixDirection: HelixDirection = .outsideIn
    private let selectable: [RampType] = [.none, .linear, .helix, .zigZag]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(selectable, id: \.self) { candidate in
                    RampTypeCard(
                        type: candidate,
                        angle: angle,
                        length: length,
                        stepdown: stepdown,
                        linearReturnMode: linearReturnMode,
                        helixDirection: helixDirection,
                        isSelected: type == candidate
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            type = candidate
                        }
                    }
                    .accessibilityAddTraits(type == candidate ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }
}

private struct RampTypeCard: View {
    let type: RampType
    let angle: Double
    let length: Double
    let stepdown: Double
    let linearReturnMode: LinearRampReturnMode
    let helixDirection: HelixDirection
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.rampCardBackground)
                // For `.none` this renders as a plain empty box — no icon, by design.
                RampVisualization(
                    type: type,
                    angle: angle,
                    length: length,
                    stepdown: stepdown,
                    mode: .topPreview,
                    linearReturnMode: linearReturnMode,
                    helixDirection: helixDirection
                )
                .padding(10)
            }
            .frame(width: RampGeometry.previewSize, height: RampGeometry.previewSize)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 6, y: 2)
            Text(type.rawValue)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Linear: top view for the compact ramp-type card

struct LinearRampTopView: View {
    let angle: Double
    let length: Double
    let stepdown: Double
    private let cycleDuration: Double = 2.2

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let result = RampMath.linearRampOutcome(angle: angle, length: length, stepdown: stepdown)
            TimelineView(.animation) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)
                Canvas { context, _ in
                    draw(context: &context, size: size, result: result, phase: currentPhase)
                }
            }
        }
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        result: (usedLength: Double, depth: Double, reachesStepdown: Bool),
        phase: CGFloat
    ) {
        let inset = min(size.width, size.height) * 0.14
        let surfaceY = size.height * 0.50
        let startX = inset
        let availableWidth = size.width - inset * 2
        let rampFraction = min(max(result.usedLength / max(length, 0.1), 0.18), 1.0)
        let endX = startX + availableWidth * rampFraction
        // Stock/pocket footprint, viewed from above.
        let stock = CGRect(x: inset, y: size.height * 0.23, width: size.width - inset * 2, height: size.height * 0.54)
        context.stroke(Path(roundedRect: stock, cornerRadius: 7), with: .color(.secondary.opacity(0.45)), lineWidth: 1)
        // A linear ramp is a straight XY travel line from the entry point.
        let start = CGPoint(x: startX, y: surfaceY)
        let end = CGPoint(x: endX, y: surfaceY)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(result.reachesStepdown ? .accentColor : .orange), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        context.fill(arrowhead(at: end, direction: CGVector(dx: 1, dy: 0), length: 8, width: 6), with: .color(result.reachesStepdown ? .accentColor : .orange))
        // Tool position is animated along the XY entry path.
        let toolX = start.x + (end.x - start.x) * phase
        context.fill(Path(ellipseIn: CGRect(x: toolX - 4, y: surfaceY - 4, width: 8, height: 8)), with: .color(.primary))
        // Subtle depth cue: deeper ramps are represented by a progressively darker tail.
        context.fill(Path(ellipseIn: CGRect(x: start.x - 2, y: surfaceY - 2, width: 4, height: 4)), with: .color(.secondary))
    }
}

// MARK: - Linear: material cross-section (side view)

struct LinearRampProfileView: View {
    let angle: Double
    let length: Double
    let stepdown: Double
    var returnMode: LinearRampReturnMode = .retrace
    private let cycleDuration: Double = 2.8

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = makeLayout(in: size)

            TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)

                Canvas { context, _ in
                    draw(
                        context: &context,
                        size: size,
                        layout: layout,
                        phase: currentPhase
                    )
                }
            }
        }
    }

    private struct Layout {
        let points: [CGPoint]
        let stepdownY: CGFloat
        let reachesStepdown: Bool
    }

    private func makeLayout(in size: CGSize) -> Layout {
        let marginX = size.width * 0.08
        let topMargin = size.height * 0.14
        let bottomMargin = size.height * 0.10

        let availableWidth = size.width - marginX * 2
        let availableHeight = size.height - topMargin - bottomMargin

        let result = RampMath.linearRampOutcome(
            angle: angle,
            length: length,
            stepdown: stepdown
        )

        let angleRadians = RampMath.clampedAngle(angle) * .pi / 180
        let slope = tan(angleRadians)

        // The ramp should occupy almost the entire width.
        let rampWidth = availableWidth

        // Calculate the depth that this horizontal distance would produce
        // at the real angle.
        let geometricDepth = rampWidth * slope

        // Scale the entire profile uniformly when the requested angle would
        // otherwise extend beyond the available vertical space.
        let scale = geometricDepth > availableHeight
            ? availableHeight / geometricDepth
            : 1.0

        let finalRampWidth = rampWidth * scale
        let finalDepth = geometricDepth * scale

        // Keep the ramp centered horizontally.
        let startX = (size.width - finalRampWidth) / 2
        let surfaceY = topMargin

        let rampEndX = startX + finalRampWidth
        let rampEndY = surfaceY + finalDepth

        // The visual ramp represents the requested physical angle.
        let rampEnd = CGPoint(
            x: rampEndX,
            y: rampEndY
        )

        let start = CGPoint(
            x: startX,
            y: surfaceY
        )

        let stageTwo: CGPoint

        if result.reachesStepdown {
            switch returnMode {
            case .advance:
                stageTwo = CGPoint(
                    x: size.width - marginX,
                    y: rampEndY
                )

            case .retrace:
                stageTwo = CGPoint(
                    x: startX,
                    y: rampEndY
                )
            }
        } else {
            stageTwo = rampEnd
        }

        // Stepdown line is positioned using the same vertical scale as
        // the ramp, so it remains geometrically consistent.
        let depthScale = finalDepth / max(result.depth, 0.01)

        let stepdownY = surfaceY + CGFloat(stepdown) * depthScale

        return Layout(
            points: [start, rampEnd, stageTwo],
            stepdownY: stepdownY,
            reachesStepdown: result.reachesStepdown
        )
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        layout: Layout,
        phase: CGFloat
    ) {
        let points = layout.points
        guard points.count == 3 else { return }

        let start = points[0]
        let rampEnd = points[1]
        let stageTwo = points[2]

        let surfaceY = start.y
        let rampColor: Color = layout.reachesStepdown ? .accentColor : .orange

        // Material below the stock surface.
        var material = Path()
        material.move(to: CGPoint(x: 0, y: surfaceY))
        material.addLine(to: CGPoint(x: size.width, y: surfaceY))
        material.addLine(to: CGPoint(x: size.width, y: size.height))
        material.addLine(to: CGPoint(x: 0, y: size.height))
        material.closeSubpath()

        context.fill(
            material,
            with: .color(.brown.opacity(0.18))
        )

        // Stock surface.
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: 0, y: surfaceY))
                p.addLine(to: CGPoint(x: size.width, y: surfaceY))
            },
            with: .color(.secondary),
            lineWidth: 1
        )

        // Maximum allowed stepdown.
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: 0, y: layout.stepdownY))
                p.addLine(to: CGPoint(x: size.width, y: layout.stepdownY))
            },
            with: .color(.secondary.opacity(0.5)),
            style: StrokeStyle(
                lineWidth: 1,
                dash: [3, 3]
            )
        )

        if layout.reachesStepdown {
            // Stage 2: movement at full depth.
            context.stroke(
                Path { p in
                    p.move(to: rampEnd)
                    p.addLine(to: stageTwo)
                },
                with: .color(.accentColor.opacity(0.45)),
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    dash: [5, 3]
                )
            )

            let direction = CGVector(
                dx: stageTwo.x - rampEnd.x,
                dy: stageTwo.y - rampEnd.y
            )

            if direction.dx != 0 || direction.dy != 0 {
                context.fill(
                    arrowhead(
                        at: stageTwo,
                        direction: direction
                    ),
                    with: .color(.accentColor.opacity(0.7))
                )
            }
        } else {
            // The available ramp length is insufficient to reach stepdown.
            // Show where the ramp would need to continue.
            let angleRadians = RampMath.clampedAngle(angle) * .pi / 180
            let remainingWidth = min(
                36,
                size.width * 0.15
            )

            let verticalScale = (
                layout.stepdownY - surfaceY
            ) / CGFloat(max(stepdown, 0.01))

            let horizontalScale = (
                rampEnd.x - start.x
            ) / CGFloat(max(length, 0.1))

            let ghostEnd = CGPoint(
                x: rampEnd.x + remainingWidth,
                y: rampEnd.y
                    + remainingWidth
                    * CGFloat(tan(angleRadians))
                    * (verticalScale / horizontalScale)
            )

            context.stroke(
                Path { p in
                    p.move(to: rampEnd)
                    p.addLine(to: ghostEnd)
                },
                with: .color(.orange.opacity(0.5)),
                style: StrokeStyle(
                    lineWidth: 1.5,
                    dash: [2, 3]
                )
            )
        }

        // Main ramp.
        context.stroke(
            Path { p in
                p.move(to: start)
                p.addLine(to: rampEnd)
            },
            with: .color(rampColor),
            style: StrokeStyle(
                lineWidth: 3,
                lineCap: .round
            )
        )

        // Entry marker.
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: start.x - 3,
                    y: start.y - 3,
                    width: 6,
                    height: 6
                )
            ),
            with: .color(.secondary)
        )

        // Animated tool position.
        let dot = point(
            along: points,
            phase: phase
        )

        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: dot.x - 5,
                    y: dot.y - 5,
                    width: 10,
                    height: 10
                )
            ),
            with: .color(rampColor)
        )
    }
}

// MARK: - Helix: top view, spiral plunge

struct HelixTopView: View {
    let angle: Double
    let length: Double
    var direction: HelixDirection = .outsideIn
    private let cycleDuration: Double = 3.0
    /// Reference diameter (mm) that fills the available drawing area — same
    /// convention as the linear and zig-zag views, so `length` visibly
    /// changes the spiral size instead of being ignored.
    private let referenceLength: Double = 30
    private let minSizeFraction: CGFloat = 0.35

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = spiralPoints(in: size)
            TimelineView(.animation) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)
                Canvas { context, _ in
                    draw(context: &context, size: size, points: points, phase: currentPhase)
                }
            }
        }
    }

    /// Outer spiral radius, scaled by `length` relative to `referenceLength`
    /// (capped at the available canvas radius either way).
    private func outerRadius(in size: CGSize) -> CGFloat {
        let maxRadius = min(size.width, size.height) / 2 - 6
        let sizeFraction = min(max(CGFloat(length / referenceLength), minSizeFraction), 1.0)
        return maxRadius * sizeFraction
    }

    private func spiralPoints(in size: CGSize) -> [CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = outerRadius(in: size)
        let innerRadius = outerRadius * 0.55
        let turns = RampMath.helixTurns(angle: angle)
        let pointsPerTurn = 40
        let totalPoints = turns * pointsPerTurn
        // Start/end radius flip with direction; `t` still runs 0 → 1 as the
        // cut progresses, so the depth-fade in `draw` stays correct either way.
        let startRadius = direction == .outsideIn ? outerRadius : innerRadius
        let endRadius = direction == .outsideIn ? innerRadius : outerRadius
        return (0...totalPoints).map { i in
            let t = CGFloat(i) / CGFloat(totalPoints)
            let radius = startRadius + (endRadius - startRadius) * t
            let theta = t * CGFloat(turns) * 2 * .pi
            return CGPoint(
                x: center.x + radius * cos(theta),
                y: center.y + radius * sin(theta)
            )
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, points: [CGPoint], phase: CGFloat) {
        guard points.count > 1 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = outerRadius(in: size)
        // Pocket / bore outline.
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2)),
            with: .color(.secondary.opacity(0.4)),
            lineWidth: 1
        )
        // Spiral, fading in as it goes — lighter (shallow) to solid (deep),
        // regardless of which way the radius itself is moving.
        for i in 0..<(points.count - 1) {
            let t = Double(i) / Double(points.count)
            var segment = Path()
            segment.move(to: points[i])
            segment.addLine(to: points[i + 1])
            context.stroke(segment, with: .color(.accentColor.opacity(0.35 + 0.65 * t)), lineWidth: 2)
        }
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
            with: .color(.secondary)
        )
        // Arrow at the very start of the spiral, showing entry direction.
        if points.count > 2 {
            let start = points[0]
            let startDirection = CGVector(dx: points[2].x - points[0].x, dy: points[2].y - points[0].y)
            context.fill(
                arrowhead(at: start, direction: CGVector(dx: -startDirection.dx, dy: -startDirection.dy)),
                with: .color(.accentColor.opacity(0.6))
            )
        }
        // Animated tool position.
        let dot = point(along: points, phase: phase)
        context.fill(
            Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
            with: .color(.accentColor)
        )
    }
}

// MARK: - ZigZag: top view, alternating diagonal passes

struct ZigZagTopView: View {
    let angle: Double
    let length: Double
    private let cycleDuration: Double = 2.6
    /// Reference ramp length (mm) that fills the full available width.
    /// Shorter ramps occupy proportionally less of the channel.
    private let referenceLength: Double = 30
    private let minWidthFraction: CGFloat = 0.3

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = zigZagPoints(in: size)
            TimelineView(.animation) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)
                Canvas { context, _ in
                    draw(context: &context, size: size, points: points, phase: currentPhase)
                }
            }
        }
    }

    private func zigZagPoints(in size: CGSize) -> [CGPoint] {
        let marginX = size.width * 0.1
        let top = size.height * 0.3
        let bottom = size.height * 0.7
        let toothCount = RampMath.zigZagPasses(angle: angle, length: length)
        // The pattern's footprint reflects `length` — a short ramp visibly
        // uses only part of the channel instead of always filling the canvas.
        let widthFraction = min(max(CGFloat(length / referenceLength), minWidthFraction), 1.0)
        let usableWidth = size.width - marginX * 2
        let patternWidth = usableWidth * widthFraction
        let startX = marginX + (usableWidth - patternWidth) / 2
        let stepX = patternWidth / CGFloat(toothCount)
        var points: [CGPoint] = []
        var isTop = true
        for i in 0...toothCount {
            let x = startX + stepX * CGFloat(i)
            let y = isTop ? top : bottom
            points.append(CGPoint(x: x, y: y))
            isTop.toggle()
        }
        return points
    }

    private func draw(context: inout GraphicsContext, size: CGSize, points: [CGPoint], phase: CGFloat) {
        guard points.count > 1 else { return }
        let top = points.map(\.y).min() ?? 0
        let bottom = points.map(\.y).max() ?? size.height
        // Channel / slot walls span the full width, showing the zig-zag
        // pattern only occupies part of it when the ramp length is short.
        for y in [top, bottom] {
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                },
                with: .color(.secondary.opacity(0.3)),
                lineWidth: 1
            )
        }
        // The zig-zag tool path, fading darker with each pass to show
        // progressive depth — same convention as the helix view.
        for i in 0..<(points.count - 1) {
            let t = Double(i) / Double(points.count - 1)
            var segment = Path()
            segment.move(to: points[i])
            segment.addLine(to: points[i + 1])
            context.stroke(
                segment,
                with: .color(.accentColor.opacity(0.35 + 0.65 * t)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        // Arrowheads at each direction change, so the back-and-forth motion reads clearly.
        for i in 1..<(points.count - 1) {
            let incoming = CGVector(dx: points[i].x - points[i - 1].x, dy: points[i].y - points[i - 1].y)
            context.fill(
                arrowhead(at: points[i], direction: incoming, length: 6, width: 4),
                with: .color(.accentColor.opacity(0.8))
            )
        }
        // Animated tool position.
        let dot = point(along: points, phase: phase)
        context.fill(
            Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
            with: .color(.accentColor)
        )
    }
}

// MARK: - Editor

struct RampingEditor: View {
    @Binding var ramping: RampingSettings
    /// Max Z the ramp may descend before cutting at full depth. This comes
    /// from your existing cutting parameters (depth-per-pass / stepdown),
    /// not from RampingSettings — passed in so the diagrams can enforce it.
    let stepdown: Double
    @Environment(\.dismiss)
    private var dismiss
    // See the note at the top of this file — move these onto RampingSettings
    // once you're ready to persist them.
    @State private var linearReturnMode: LinearRampReturnMode = .retrace
    @State private var helixDirection: HelixDirection = .outsideIn

    var body: some View {
        Form {
            Section {
                RampTypeSelector(
                    type: $ramping.type,
                    angle: ramping.angle,
                    length: ramping.length,
                    stepdown: stepdown,
                    linearReturnMode: linearReturnMode,
                    helixDirection: helixDirection
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } header: {
                Text("Ramp type")
            }

            Section {
                RampVisualization(
                    type: ramping.type,
                    angle: ramping.angle,
                    length: ramping.length,
                    stepdown: stepdown,
                    mode: .profileDetail,
                    linearReturnMode: linearReturnMode,
                    helixDirection: helixDirection
                )
                .frame(height: RampGeometry.detailSize)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.rampCardBackground)
                )
                .animation(.easeInOut(duration: 0.2), value: ramping.type)

                if ramping.type == .linear {
                    Picker("Return path", selection: $linearReturnMode) {
                        ForEach(LinearRampReturnMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if ramping.type == .helix {
                    Picker("Spiral direction", selection: $helixDirection) {
                        ForEach(HelixDirection.allCases) { dir in
                            Text(dir.rawValue).tag(dir)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Text(rampDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !rampMetrics.isEmpty {
                    Text(rampMetrics)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if ramping.type != .none {
                Section {
                    HStack {
                        Text("Ramp angle")
                        Spacer()
                        TextField(
                            "",
                            value: $ramping.angle,
                            format: .number
                        )
                        .multilineTextAlignment(.trailing)
                        Text("°")
                            .foregroundStyle(.secondary)
                    }

                    if ramping.type == .linear {
                        HStack {
                            Text("Required ramp distance")
                            Spacer()
                            Text(String(format: "%.2f mm", linearRampLength))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("Calculated automatically from the angle and current stepdown. It is not editable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Ramp length")
                            Spacer()
                            TextField(
                                "",
                                value: $ramping.length,
                                format: .number
                            )
                            .multilineTextAlignment(.trailing)
                            Text("mm")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear {
            syncLinearRampLength()
        }
        .onChange(of: ramping.type) { _ in
            syncLinearRampLength()
        }
        .onChange(of: ramping.angle) { _ in
            syncLinearRampLength()
        }
        .onChange(of: stepdown) { _ in
            syncLinearRampLength()
        }
        .padding(16)
    }

    private func syncLinearRampLength() {
        guard ramping.type == .linear else { return }
        ramping.length = linearRampLength
    }

    private var linearRampLength: Double {
        RampMath.linearRequiredLength(angle: ramping.angle, stepdown: stepdown)
    }

    private var rampDescription: String {
        switch ramping.type {
        case .none:
            return "The tool plunges vertically."
        case .linear:
            let result = RampMath.linearRampOutcome(angle: ramping.angle, length: ramping.length, stepdown: stepdown)
            let stageText: String
            switch linearReturnMode {
            case .advance:
                stageText = "continues forward into the cut"
            case .retrace:
                stageText = "retraces back to the start point"
            }
            if result.reachesStepdown {
                return "The tool descends at \(String(format: "%.1f", ramping.angle))° to reach the \(String(format: "%.2f", stepdown)) mm stepdown, then \(stageText). The required distance is calculated automatically."
            } else {
                return "⚠️ At this angle, \(String(format: "%.1f", ramping.length)) mm of ramp length only reaches \(String(format: "%.2f", result.depth)) mm — short of the \(String(format: "%.2f", stepdown)) mm stepdown. Increase length or use a shallower angle."
            }
        case .helix:
            switch helixDirection {
            case .outsideIn:
                return "The tool spirals downward from the outside edge inward, shown here from above."
            case .insideOut:
                return "The tool spirals downward from the center outward, shown here from above."
            }
        case .zigZag:
            return "The tool descends using alternating diagonal passes over the ramp length, shown here from above."
        }
    }

    private var rampMetrics: String {
        switch ramping.type {
        case .linear:
            let result = RampMath.linearRampOutcome(angle: ramping.angle, length: ramping.length, stepdown: stepdown)
            if result.reachesStepdown {
                return String(format: "Required distance: %.2f mm at %.1f°", result.usedLength, RampMath.clampedAngle(ramping.angle))
            } else {
                return String(format: "Needs ≥ %.1f mm at this angle to reach stepdown", RampMath.linearRequiredLength(angle: ramping.angle, stepdown: stepdown))
            }
        case .helix:
            let turns = RampMath.helixTurns(angle: ramping.angle)
            return "≈ \(turns) turn\(turns == 1 ? "" : "s") to reach depth"
        case .zigZag:
            let passes = RampMath.zigZagPasses(angle: ramping.angle, length: ramping.length)
            return "≈ \(passes) alternating pass\(passes == 1 ? "" : "es")"
        case .none:
            return ""
        }
    }
}
