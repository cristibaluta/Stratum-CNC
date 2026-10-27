//
//  PatternPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 22.09.2026.
//

import SwiftUI

/// Chooses how a pocket is cleared. Same look as `OperationPicker`.
struct PatternPicker: View {
    @Binding var pattern: PocketPattern

    /// The patterns on offer, in order -- what the operation accepts, as the library says.
    var available: [PocketPattern] = PocketPattern.allCases

    @State private var isPresented = false

    var body: some View {
        InspectorRow(label: "Pattern") {
            Button {
                isPresented.toggle()
            } label: {
                InspectorMenuLabel {
                    PatternGlyph(pattern: pattern)
                        .frame(width: 18, height: 14)
                    Text(pattern.rawValue)
                }
            }
            .buttonStyle(.plain)
            .help(pattern.selectionHint)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                PatternGridPicker(pattern: $pattern, available: available, isPresented: $isPresented)
            }
        }
    }
}

/// The tooltip-style popover content: every pattern, laid out as a row of
/// glyph + label tiles instead of `Menu`'s single vertical list.
private struct PatternGridPicker: View {
    @Binding var pattern: PocketPattern
    let available: [PocketPattern]
    @Binding var isPresented: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    private let tileSize = CGSize(width: 70, height: 56)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(available, id: \.self) { option in
                tile(for: option)
            }
        }
        .padding(10)
        .frame(width: CGFloat(columns.count) * tileSize.width + CGFloat(columns.count - 1) * 6 + 20)
    }

    private func tile(for option: PocketPattern) -> some View {
        let isSelected = option == pattern

        return Button {
            pattern = option
            isPresented = false
        } label: {
            VStack(spacing: 4) {
                PatternGlyph(pattern: option, tint: isSelected ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 22)

                Text(option.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: tileSize.width, height: tileSize.height)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(option.selectionHint)
    }
}

/// A small drawing of the tool's path filling a pocket: nested rings for an offset,
/// scanlines for a raster, a tightening spiral, looping coils for a trochoid, and a helix with
/// growing partial passes for adaptive —
/// all against the pocket's boundary (solid), same convention as `ContourTypeGlyph`.
private struct PatternGlyph: View {
    let pattern: PocketPattern
    var tint: Color = .primary

    private let partInset: CGFloat = 2

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .inset(by: partInset)
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1.1)

            GeometryReader { proxy in
                fillPath(in: proxy.size)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func fillPath(in size: CGSize) -> Path {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: partInset + 3, dy: partInset + 3)
        switch pattern {
            case .offset:     return offsetPath(in: rect)
            case .raster:     return rasterPath(in: rect)
            case .spiral:     return spiralPath(in: rect)
            case .trochoidal: return trochoidalPath(in: rect)
            case .concentric: return spiralPath(in: rect)
            case .adaptive:   return adaptivePath(in: rect)
        }
    }

    /// Shrinking rings tracing the boundary inward, one pass per ring.
    private func offsetPath(in rect: CGRect) -> Path {
        var path = Path()
        let ringCount = 2
        let step = min(rect.width, rect.height) / CGFloat(ringCount * 2 + 1)
        for i in 1...ringCount {
            let r = rect.insetBy(dx: CGFloat(i) * step, dy: CGFloat(i) * step)
            guard r.width > 1, r.height > 1 else {
                continue
            }
            path.addRoundedRect(in: r, cornerSize: CGSize(width: 1.5, height: 1.5))
        }
        return path
    }

    /// Parallel scanlines sweeping back and forth.
    private func rasterPath(in rect: CGRect) -> Path {
        var path = Path()
        let lineCount = 4
        guard lineCount > 1 else {
            return path
        }
        let step = rect.height / CGFloat(lineCount - 1)

        for i in 0..<lineCount {
            let y = rect.minY + CGFloat(i) * step
            if i.isMultiple(of: 2) {
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            } else {
                path.move(to: CGPoint(x: rect.maxX, y: y))
                path.addLine(to: CGPoint(x: rect.minX, y: y))
            }
        }
        return path
    }

    /// A tightening spiral from the boundary down to the centre.
    private func spiralPath(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2
        let turns: CGFloat = 2.25
        let segments = 48

        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let angle = t * turns * 2 * .pi
            let radius = maxRadius * (1 - t)
            let point = CGPoint(x: center.x + radius * cos(angle),
                                 y: center.y + radius * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    /// A small helix circle in the middle, with the wavefront growing out from it in
    /// partial, rounded passes that never close into full rings.
    private func adaptivePath(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let unit = min(rect.width, rect.height)
        let helixRadius = unit * 0.14

        path.addEllipse(in: CGRect(x: center.x - helixRadius,
                                   y: center.y - helixRadius,
                                   width: helixRadius * 2,
                                   height: helixRadius * 2))

        // (distance from the helix, how much of the ring is drawn)
        let passes: [(CGFloat, CGFloat)] = [(0.18, 0.82), (0.34, 0.62)]
        for (distance, drawn) in passes {
            let half = helixRadius + unit * distance
            let ring = CGRect(x: center.x - half * 1.5,
                              y: center.y - half,
                              width: half * 3,
                              height: half * 2)
            guard ring.width <= rect.width + 0.5, ring.height <= rect.height + 0.5 else {
                continue
            }
            path.addPath(RoundedRectangle(cornerRadius: half * 0.6)
                .path(in: ring)
                .trimmedPath(from: 0.05, to: drawn))
        }
        return path
    }

    /// A straight travel line with the small looping coils a trochoid traces
    /// as it steps forward.
    private func trochoidalPath(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))

        let loopCount = 3
        let loopRadius = rect.height * 0.42
        let spacing = rect.width / CGFloat(loopCount)

        for i in 0..<loopCount {
            let cx = rect.minX + spacing * (CGFloat(i) + 0.5)
            let loopRect = CGRect(x: cx - loopRadius,
                                  y: y - loopRadius,
                                  width: loopRadius * 2,
                                  height: loopRadius * 2)
            path.addEllipse(in: loopRect)
        }
        return path
    }
}

private extension PocketPattern {
    var selectionHint: String {
        switch self {
            case .offset:     return "Clears with rings that follow the pocket's shape, working inward."
            case .raster:     return "Clears with straight back-and-forth passes."
            case .spiral:     return "Clears with a continuous, tightening spiral."
            case .trochoidal: return "Clears with small looping passes, easing tool load in slots and tight corners."
            case .concentric: return "Clears with rings that expand outward."
            case .adaptive:   return "Clears with a constant, light radial load: opens up from a helix in the middle, so the tool never buries itself in corners."
        }
    }
}

#Preview {
    @Previewable @State var pattern = PocketPattern.spiral
    PatternPicker(pattern: $pattern)
        .padding()
}
