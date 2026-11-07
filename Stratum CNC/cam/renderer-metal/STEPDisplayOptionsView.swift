//
//  STEPDisplayOptionsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.11.2026.
//


//
//  STEPDisplayOptionsView.swift
//  Stratum CNC
//
//  The popover behind the cube button on the canvas: how the STEP model is drawn, and how its
//  edges behind a face are drawn. Every choice is a tile with a small drawing of a part in that
//  style, so what will happen is visible before it is picked. The drawings follow the current
//  settings (the "Hidden edges" tiles show the current display mode, and the "Display" tiles the
//  current hidden-edge style), so each tile shows what clicking it will give.
//

import SwiftUI

struct STEPDisplayOptionsView: View {
    @ObservedObject var scene: STEPDocumentScene

    /// What the drawings show for hidden edges: a model without surfaces draws every edge solid.
    private var effectiveHidden: STEPHiddenEdgeMode {
        scene.hasSurfaces ? scene.hiddenEdgeMode : .solid
    }

    private var displayEnabled: Bool { scene.isModelVisible }

    private var hiddenEdgesEnabled: Bool {
        scene.hasSurfaces && scene.isModelVisible && scene.displayMode != .shaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(title: "Display", detail: scene.displayMode.detail) {
                ForEach(STEPDisplayMode.allCases) { mode in
                    STEPOptionTile(title: mode.label,
                                   isSelected: scene.displayMode == mode,
                                   isEnabled: displayEnabled && (mode == .wireframe || scene.canShade)) {
                        withAnimation(.easeOut(duration: 0.15)) { scene.displayMode = mode }
                    } glyph: {
                        STEPPartGlyph(mode: mode, hidden: effectiveHidden)
                    }
                }
            }
            if let reason = scene.shadedUnavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }

            section(title: "Edges behind faces", detail: hiddenEdgesEnabled ? effectiveHidden.detail : nil) {
                ForEach(STEPHiddenEdgeMode.allCases) { mode in
                    STEPOptionTile(title: mode.label,
                                   isSelected: effectiveHidden == mode,
                                   isEnabled: hiddenEdgesEnabled) {
                        withAnimation(.easeOut(duration: 0.15)) { scene.hiddenEdgeMode = mode }
                    } glyph: {
                        // Shown in the current display mode, except plain shaded, which has no edges
                        STEPPartGlyph(mode: scene.displayMode == .shadedEdges ? .shadedEdges : .wireframe,
                                      hidden: mode)
                    }
                }
            }
            if scene.displayMode == .shaded {
                Text("Shaded draws no edges, so there is nothing to pick yet. Use Shaded + edges to select edges.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if scene.hasSurfaces, !scene.content.surfaces.unsurfacedBodies.isEmpty {
                Text("Bodies with unsupported faces keep solid edges.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !scene.hasSurfaces {
                Text("This model has no faces to hide edges behind, so every edge is drawn.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func section<Content: View>(title: String, detail: String?,
                                        @ViewBuilder tiles: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack(spacing: 10) { tiles() }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension STEPDisplayMode {
    var detail: String {
        switch self {
            case .wireframe: return "Edges only, see-through."
            case .shaded: return "Lit faces, no edges."
            case .shadedEdges: return "Lit faces with the edges drawn on top."
        }
    }
}

private extension STEPHiddenEdgeMode {
    var detail: String {
        switch self {
            case .dotted: return "Edges behind a face are drawn as dots."
            case .hidden: return "Edges behind a face are not drawn."
            case .solid: return "Edges behind a face are drawn like the others."
        }
    }
}

// MARK: - Tile

/// A choice: a drawing on a card and its name under it, in the look of `RampTypeCard`.
private struct STEPOptionTile<Glyph: View>: View {
    let title: String
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.rampCardBackground))
                    glyph().padding(8)
                }
                .frame(height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 6, y: 2)
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Glyph

/// A cube seen from the front, above and the right, drawn the way the canvas draws a part: the
/// edges of the three visible faces, plus the three edges at the far lower-left corner, which lie
/// behind the faces and so follow the hidden-edge style.
struct STEPPartGlyph: View {
    let mode: STEPDisplayMode
    var hidden: STEPHiddenEdgeMode = .dotted

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) * 0.56
            let depth = side * 0.42
            let x0 = (size.width - side - depth) / 2
            let top = (size.height - side - depth) / 2

            // Corners: front face, and the back face shifted up and to the right.
            let ftl = CGPoint(x: x0, y: top + depth)
            let ftr = CGPoint(x: x0 + side, y: top + depth)
            let fbl = CGPoint(x: x0, y: top + depth + side)
            let fbr = CGPoint(x: x0 + side, y: top + depth + side)
            func back(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + depth, y: p.y - depth) }
            let btl = back(ftl), btr = back(ftr), bbl = back(fbl), bbr = back(fbr)

            let ink = Color.primary

            // Faces: lit from above and the left, so the top is the lightest and the right the darkest.
            if mode != .wireframe {
                func fill(_ points: [CGPoint], _ opacity: Double) {
                    var path = Path()
                    path.addLines(points)
                    path.closeSubpath()
                    context.fill(path, with: .color(ink.opacity(opacity)))
                }
                fill([ftl, ftr, btr, btl], 0.10)
                fill([ftl, ftr, fbr, fbl], 0.24)
                fill([ftr, btr, bbr, fbr], 0.38)
            }

            func line(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points)
                return path
            }

            // The edges behind the faces.
            if mode != .shaded, hidden != .hidden {
                let style = StrokeStyle(lineWidth: 1.1, lineCap: .round,
                                        dash: hidden == .dotted ? [0.1, 3] : [])
                let opacity = hidden == .dotted ? 0.7 : 0.9
                for hiddenEdge in [[fbl, bbl], [bbl, btl], [bbl, bbr]] {
                    context.stroke(line(hiddenEdge), with: .color(ink.opacity(opacity)), style: style)
                }
            }

            // The edges in front.
            if mode != .shaded {
                let style = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                for edge in [[ftl, ftr, fbr, fbl, ftl],      // front face
                             [ftl, btl, btr, ftr],           // top face, back and sides
                             [btr, bbr, fbr]] {              // right face, back and bottom
                    context.stroke(line(edge), with: .color(ink.opacity(0.9)), style: style)
                }
            }
        }
        .accessibilityHidden(true)
    }
}