//
//  RampingEditor.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//
//  Assumes, unchanged, elsewhere in the project:
//    enum RampType: String, CaseIterable { case none, linear, helix, zigZag }
//    struct RampingSettings { var enabled: Bool; var type: RampType; var angle: Double; var length: Double }
//

import SwiftUI

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
}

// MARK: - Path-following helper (drives the animated tool dot)

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
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

// MARK: - Layout constants

enum RampGeometry {
    static let previewSize: CGFloat = 88
    static let detailSize: CGFloat = 220
}

// MARK: - Visualization dispatcher

struct RampVisualization: View {
    let type: RampType
    let angle: Double
    let length: Double

    var body: some View {
        switch type {
        case .linear:
            LinearRampProfileView(angle: angle, length: length)
        case .helix:
            HelixTopView(angle: angle, length: length)
        case .zigZag:
            ZigZagTopView(angle: angle, length: length)
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

    private let selectable: [RampType] = [.linear, .helix, .zigZag]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(selectable, id: \.self) { candidate in
                RampTypeCard(
                    type: candidate,
                    angle: angle,
                    length: length,
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

private struct RampTypeCard: View {
    let type: RampType
    let angle: Double
    let length: Double
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor))
                RampVisualization(type: type, angle: angle, length: length)
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

// MARK: - Linear: material cross-section (side view)

struct LinearRampProfileView: View {
    let angle: Double
    let length: Double

    private let cycleDuration: Double = 2.6

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = pathPoints(in: size)

            TimelineView(.animation) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)
                Canvas { context, _ in
                    draw(context: &context, size: size, points: points, phase: currentPhase)
                }
            }
        }
    }

    /// Entry point, ramp bottom and a short flat run-out, in view-local coordinates.
    /// Uses a single uniform scale for x and y so the drawn angle matches the real one.
    private func pathPoints(in size: CGSize) -> [CGPoint] {
        let margin = size.width * 0.12
        let clampedLength = max(length, 0.1)
        let depth = RampMath.linearDepth(angle: angle, length: length)

        let maxDimension = max(clampedLength, depth, 0.1)
        let available = min(size.width, size.height) - margin * 2
        let scale = available / CGFloat(maxDimension)

        let surfaceY = size.height * 0.28
        let startX = margin
        let endX = startX + CGFloat(clampedLength) * scale
        let endY = surfaceY + CGFloat(depth) * scale
        let runOutX = min(endX + (endX - startX) * 0.4, size.width - margin * 0.4)

        return [
            CGPoint(x: startX, y: surfaceY),
            CGPoint(x: endX, y: endY),
            CGPoint(x: runOutX, y: endY)
        ]
    }

    private func draw(context: inout GraphicsContext, size: CGSize, points: [CGPoint], phase: CGFloat) {
        guard points.count == 3 else { return }
        let surfaceY = points[0].y

        // Material block below the surface line.
        var material = Path()
        material.move(to: CGPoint(x: 0, y: surfaceY))
        material.addLine(to: CGPoint(x: size.width, y: surfaceY))
        material.addLine(to: CGPoint(x: size.width, y: size.height))
        material.addLine(to: CGPoint(x: 0, y: size.height))
        material.closeSubpath()
        context.fill(material, with: .color(.brown.opacity(0.18)))

        // Stock surface.
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: 0, y: surfaceY))
                p.addLine(to: CGPoint(x: size.width, y: surfaceY))
            },
            with: .color(.secondary),
            lineWidth: 1
        )

        // Faint continuation, to suggest the cut keeps going at depth.
        context.stroke(
            Path { p in
                p.move(to: points[1])
                p.addLine(to: points[2])
            },
            with: .color(.accentColor.opacity(0.4)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 3])
        )

        // The ramp entry itself, emphasised.
        context.stroke(
            Path { p in
                p.move(to: points[0])
                p.addLine(to: points[1])
            },
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
        )

        // Animated tool position.
        let dot = point(along: points, phase: phase)
        context.fill(
            Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
            with: .color(.accentColor)
        )
    }
}

// MARK: - Helix: top view, spiral plunge

struct HelixTopView: View {
    let angle: Double
    let length: Double

    private let cycleDuration: Double = 3.0

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

    private func spiralPoints(in size: CGSize) -> [CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = min(size.width, size.height) / 2 - 6
        let innerRadius = outerRadius * 0.55
        let turns = RampMath.helixTurns(angle: angle)
        let pointsPerTurn = 40
        let totalPoints = turns * pointsPerTurn

        return (0...totalPoints).map { i in
            let t = CGFloat(i) / CGFloat(totalPoints)
            let radius = outerRadius - (outerRadius - innerRadius) * t
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
        let outerRadius = min(size.width, size.height) / 2 - 6

        // Pocket / bore outline.
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2)),
            with: .color(.secondary.opacity(0.4)),
            lineWidth: 1
        )

        // Spiral, fading in as it goes — lighter (shallow) to solid (deep).
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
        let margin = size.width * 0.1
        let top = size.height * 0.3
        let bottom = size.height * 0.7

        let toothCount = RampMath.zigZagPasses(angle: angle, length: length)
        let availableWidth = size.width - margin * 2
        let stepX = availableWidth / CGFloat(toothCount)

        var points: [CGPoint] = []
        var isTop = true
        for i in 0...toothCount {
            let x = margin + stepX * CGFloat(i)
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

        // Channel boundary.
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

        // The zig-zag tool path.
        var path = Path()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        context.stroke(
            path,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

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

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        Form {

            Toggle(
                "Enable ramping",
                isOn: $ramping.enabled
            )

            if ramping.enabled {

                Section {
                    RampTypeSelector(
                        type: $ramping.type,
                        angle: ramping.angle,
                        length: ramping.length
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
                        length: ramping.length
                    )
                    .frame(height: RampGeometry.detailSize)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.controlBackgroundColor))
                    )
                    .animation(.easeInOut(duration: 0.2), value: ramping.type)

                    Text(rampDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !rampMetrics.isEmpty {
                        Text(rampMetrics)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

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
        .padding(16)
    }

    private var rampDescription: String {
        switch ramping.type {
        case .none:
            return "The tool plunges vertically."

        case .linear:
            return "The tool gradually descends along a straight ramp — shown here in material cross-section."

        case .helix:
            return "The tool spirals downward while orbiting the contour — shown here from above."

        case .zigZag:
            return "The tool descends using alternating diagonal passes — shown here from above."
        }
    }

    private var rampMetrics: String {
        switch ramping.type {
        case .linear:
            let depth = RampMath.linearDepth(angle: ramping.angle, length: ramping.length)
            return String(format: "≈ %.1f mm deep over %.1f mm of travel", depth, max(ramping.length, 0.1))

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
