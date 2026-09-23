//
//  PatternPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 22.09.2026.
//

import SwiftUI

/// Chooses how a pocket is cleared. Same look as `OperationPicker` / `ContourPicker`.
struct PatternPicker: View {
    @Binding var pattern: PocketPattern

    /// When true, the options are laid out directly in the view instead of
    /// behind a button + popover.
    var expanded: Bool = false

    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CLEARING PATTERN")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if expanded {
                PatternGridPicker(pattern: $pattern, isPresented: .constant(false))
            } else {
                Button {
                    isPresented.toggle()
                } label: {
                    HStack(spacing: 5) {
                        PatternGlyph(pattern: pattern)
                            .frame(width: 18, height: 14)

                        Text(pattern.rawValue)
                            .fontWeight(.semibold)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background(Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(pattern.selectionHint)
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    PatternGridPicker(pattern: $pattern, isPresented: $isPresented)
                }
            }
        }
    }
}

/// The tooltip-style popover content: every pattern, laid out as a row of
/// glyph + label tiles instead of `Menu`'s single vertical list.
private struct PatternGridPicker: View {
    @Binding var pattern: PocketPattern
    @Binding var isPresented: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    private let tileSize = CGSize(width: 70, height: 56)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(PocketPattern.allCases, id: \.self) { option in
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
/// scanlines for a raster, a tightening spiral, and looping coils for a trochoid —
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
        }
    }

    /// Shrinking rings tracing the boundary inward, one pass per ring.
    private func offsetPath(in rect: CGRect) -> Path {
        var path = Path()
        let ringCount = 2
        let step = min(rect.width, rect.height) / CGFloat(ringCount * 2 + 1)
        for i in 1...ringCount {
            let r = rect.insetBy(dx: CGFloat(i) * step, dy: CGFloat(i) * step)
            guard r.width > 1, r.height > 1 else { continue }
            path.addRoundedRect(in: r, cornerSize: CGSize(width: 1.5, height: 1.5))
        }
        return path
    }

    /// Parallel scanlines sweeping back and forth.
    private func rasterPath(in rect: CGRect) -> Path {
        var path = Path()
        let lineCount = 4
        guard lineCount > 1 else { return path }
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
            let loopRect = CGRect(x: cx - loopRadius, y: y - loopRadius,
                                   width: loopRadius * 2, height: loopRadius * 2)
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
        }
    }
}

#Preview {
    @Previewable @State var pattern = PocketPattern.spiral
    PatternPicker(pattern: $pattern)
        .padding()
}
