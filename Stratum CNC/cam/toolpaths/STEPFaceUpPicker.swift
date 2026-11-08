//
//  STEPFaceUpPicker.swift
//  Stratum CNC
//
//  The "Face up" choice of a STEP model in the objects inspector: six tiles, each a drawing of
//  the model as imported with the face that will point up marked, so the choice can be made
//  without knowing which way the CAD file was drawn.
//

import SwiftUI

struct STEPFaceUpPicker: View {

    let selection: SetupFace
    let onSelect: (SetupFace) -> Void

    /// Rows of three, the faces in the order of the part's frame: the top and its opposite first.
    private static let rows: [[SetupFace]] = [[.top, .front, .right], [.bottom, .back, .left]]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { face in
                        tile(face)
                    }
                }
            }
            Text(selection.upDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile(_ face: SetupFace) -> some View {
        let isSelected = face == selection
        return Button { onSelect(face) } label: {
            VStack(spacing: 4) {
                STEPFaceGlyph(face: face)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.rampCardBackground)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                Text(face.title)
                    .font(.system(size: 11))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private extension SetupFace {
    /// What the picked face means, in the words of the model's own frame.
    var upDescription: String {
        switch self {
            case .top:    return "The model as it was drawn: its +Z side faces up."
            case .bottom: return "Flipped over: the model's underside (−Z) faces up."
            case .front:  return "The model's front (−Y, toward the operator) faces up."
            case .back:   return "The model's back (+Y) faces up."
            case .left:   return "The model's left side (−X) faces up."
            case .right:  return "The model's right side (+X) faces up."
        }
    }
}

/// The model as imported, as a see-through cube: its far edges dotted, and the face that will
/// point up filled.
struct STEPFaceGlyph: View {
    let face: SetupFace

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) * 0.56
            let depth = side * 0.42
            let x0 = (size.width - side - depth) / 2
            let top = (size.height - side - depth) / 2

            let ftl = CGPoint(x: x0, y: top + depth)
            let ftr = CGPoint(x: x0 + side, y: top + depth)
            let fbl = CGPoint(x: x0, y: top + depth + side)
            let fbr = CGPoint(x: x0 + side, y: top + depth + side)
            func back(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + depth, y: p.y - depth) }
            let btl = back(ftl), btr = back(ftr), bbl = back(fbl), bbr = back(fbr)

            func path(_ points: [CGPoint], closed: Bool = false) -> Path {
                var path = Path()
                path.addLines(points)
                if closed { path.closeSubpath() }
                return path
            }

            // The face that goes up, in the model's own frame as seen from the front, above and the right.
            let marked: [CGPoint]
            switch face {
                case .top:    marked = [ftl, ftr, btr, btl]
                case .bottom: marked = [fbl, fbr, bbr, bbl]
                case .front:  marked = [ftl, ftr, fbr, fbl]
                case .back:   marked = [btl, btr, bbr, bbl]
                case .left:   marked = [ftl, btl, bbl, fbl]
                case .right:  marked = [ftr, btr, bbr, fbr]
            }
            context.fill(path(marked, closed: true), with: .color(Color.accentColor.opacity(0.45)))

            let ink = Color.primary
            // Edges behind the faces
            let dotted = StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [0.1, 3])
            for edge in [[fbl, bbl], [bbl, btl], [bbl, bbr]] {
                context.stroke(path(edge), with: .color(ink.opacity(0.6)), style: dotted)
            }
            // Edges in front
            let solid = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
            for edge in [[ftl, ftr, fbr, fbl, ftl], [ftl, btl, btr, ftr], [btr, bbr, fbr]] {
                context.stroke(path(edge), with: .color(ink.opacity(0.85)), style: solid)
            }
            // An arrow up from the marked face's centre
            let center = CGPoint(x: marked.map(\.x).reduce(0, +) / 4, y: marked.map(\.y).reduce(0, +) / 4)
            var arrow = Path()
            arrow.move(to: CGPoint(x: center.x, y: center.y - 1))
            arrow.addLine(to: CGPoint(x: center.x, y: center.y - 9))
            arrow.move(to: CGPoint(x: center.x - 3, y: center.y - 6))
            arrow.addLine(to: CGPoint(x: center.x, y: center.y - 9))
            arrow.addLine(to: CGPoint(x: center.x + 3, y: center.y - 6))
            context.stroke(arrow, with: .color(Color.accentColor),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
