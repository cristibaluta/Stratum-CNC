//
//  DirectionPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 22.09.2026.
//


//
//  DirectionPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// Chooses which way the tool cuts relative to its rotation. Same look as
/// `OperationPicker` / `ContourPicker` / `PatternPicker`.
struct DirectionPicker: View {
    @Binding var direction: CutDirectionOption

    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DIRECTION")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 5) {
                    DirectionGlyph(direction: direction)
                        .frame(width: 18, height: 14)

                    Text(direction.rawValue)
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
            .help(direction.selectionHint)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                DirectionGridPicker(direction: $direction, isPresented: $isPresented)
            }
        }
    }
}

/// The tooltip-style popover content: both directions, laid out as a row of
/// glyph + label tiles instead of `Menu`'s single vertical list.
private struct DirectionGridPicker: View {
    @Binding var direction: CutDirectionOption
    @Binding var isPresented: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    private let tileSize = CGSize(width: 70, height: 56)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(CutDirectionOption.allCases, id: \.self) { option in
                tile(for: option)
            }
        }
        .padding(10)
        .frame(width: CGFloat(columns.count) * tileSize.width + CGFloat(columns.count - 1) * 6 + 20)
    }

    private func tile(for option: CutDirectionOption) -> some View {
        let isSelected = option == direction

        return Button {
            direction = option
            isPresented = false
        } label: {
            VStack(spacing: 4) {
                DirectionGlyph(direction: option, tint: isSelected ? Color.accentColor : .secondary)
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

/// A small drawing of the cutter orbiting the part boundary: the arrowed loop runs
/// clockwise for climb (the cutter's rotation and its travel agree at the edge) and
/// counter-clockwise for conventional (they oppose). Same boundary convention as
/// `ContourTypeGlyph` / `PatternGlyph`.
private struct DirectionGlyph: View {
    let direction: CutDirectionOption
    var tint: Color = .primary

    private let partInset: CGFloat = 2

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .inset(by: partInset)
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1.1)

            GeometryReader { proxy in
                orbitPath(in: proxy.size)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private var isClimb: Bool { direction == .climb }

    /// Three-quarters of a circle plus a small arrowhead at the open end, so the
    /// direction of travel reads at a glance even at icon size.
    private func orbitPath(in size: CGSize) -> Path {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: partInset + 2, dy: partInset + 2)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0 else { return Path() }

        let startAngle: CGFloat = -.pi / 2
        let sweep: CGFloat = 1.55 * .pi
        let endAngle = isClimb ? startAngle + sweep : startAngle - sweep

        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .radians(startAngle), endAngle: .radians(endAngle),
                    clockwise: !isClimb)

        // Arrowhead, tangent to the circle at the arc's open end.
        let tip = CGPoint(x: center.x + radius * cos(endAngle), y: center.y + radius * sin(endAngle))
        let travel = endAngle + (isClimb ? .pi / 2 : -.pi / 2)
        let wingSpan: CGFloat = 3.2
        let wingBack: CGFloat = 4.2
        let base = CGPoint(x: tip.x - wingBack * cos(travel), y: tip.y - wingBack * sin(travel))
        let normal = travel + .pi / 2
        let wing1 = CGPoint(x: base.x + wingSpan * cos(normal), y: base.y + wingSpan * sin(normal))
        let wing2 = CGPoint(x: base.x - wingSpan * cos(normal), y: base.y - wingSpan * sin(normal))

        path.move(to: wing1)
        path.addLine(to: tip)
        path.addLine(to: wing2)

        return path
    }
}

private extension CutDirectionOption {
    var selectionHint: String {
        switch self {
            case .climb:        return "Cutter rotation and feed agree at the edge — smoother finish, lighter chips at the end of each pass."
            case .conventional: return "Cutter rotation and feed oppose at the edge — safer bite on rigid setups and older machines."
        }
    }
}

#Preview {
    @Previewable @State var direction = CutDirectionOption.climb
    DirectionPicker(direction: $direction)
        .padding()
}