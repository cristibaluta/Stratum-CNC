//
//  STEPAddToolpathTooltipLayer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.11.2026.
//

import SwiftUI

/// The callout over the selected STEP edges: "Select linked" and "Add toolpath" on top, always
/// there (disabled when they do not apply), and under them one line with what is selected.
/// It follows the selection's top as the camera orbits, pans and zooms.
struct STEPAddToolpathTooltipLayer: View {

    @ObservedObject var scene: STEPDocumentScene
    let zoomModel: CanvasZoomModel
    let canAdd: Bool
    let onAdd: () -> Void

    @State private var frameTick = 0

    private static let gap: CGFloat = 6
    private static let minAnchorY: CGFloat = 56
    /// Half the callout's width or more, so it is never cut off at the sides of the canvas.
    private static let horizontalMargin: CGFloat = 170

    var body: some View {
        let _ = frameTick
        GeometryReader { proxy in
            if !scene.selectedEdges.isEmpty, let anchor = anchor(in: proxy.size) {
                STEPSelectionCallout(summary: Self.summary(for: scene),
                                     canSelectLinked: scene.canSelectLinkedInPlane,
                                     canAdd: canAdd,
                                     onSelectLinked: { scene.selectLinkedEdgesInPlane() },
                                     onAdd: onAdd)
                    .fixedSize()
                    .frame(width: 0, height: 0, alignment: .bottom)
                    .position(anchor)
                    .transition(.opacity)
            }
        }
        .onReceive(zoomModel.frameRendered.receive(on: DispatchQueue.main)) { _ in
            frameTick &+= 1
        }
    }

    /// The highest point of the selection's bounding box on screen, centered horizontally on it.
    private func anchor(in size: CGSize) -> CGPoint? {
        guard let box = scene.selectionBox, size.width > 0, size.height > 0 else {
            return nil
        }
        var projected: [CGPoint] = []
        for x in [box.min.x, box.max.x] {
            for y in [box.min.y, box.max.y] {
                for z in [box.min.z, box.max.z] {
                    if let point = zoomModel.normalizedViewPoint(forWorld: SIMD3<Float>(x, y, z)) {
                        projected.append(point)
                    }
                }
            }
        }
        guard let top = projected.map(\.y).min(),
              let left = projected.map(\.x).min(),
              let right = projected.map(\.x).max() else {
            return nil
        }
        let margin = min(Self.horizontalMargin, size.width / 2)
        let x = min(max((left + right) / 2 * size.width, margin), size.width - margin)
        let y = max(top * size.height - Self.gap, Self.minAnchorY)
        return CGPoint(x: x, y: y)
    }

    /// One line: how many edges, how far they are from z0, and their size. Each value has its
    /// symbol: Z height relative to z0 (negative is below it), Ø diameter of a circle, R radius
    /// of an arc, L length (of a line, or of all the edges together when there are several, an
    /// arc then counting by its length).
    static func summary(for scene: STEPDocumentScene) -> String {
        func mm(_ value: Float) -> String { String(format: "%.3f", value) }
        let count = scene.selectedEdges.count
        var parts = [count == 1 ? "1 edge" : "\(count) edges"]
        if let z = scene.selectionZRange {
            parts.append(z.upperBound - z.lowerBound < 1e-3
                         ? "Z \(mm(z.lowerBound))"
                         : "Z \(mm(z.lowerBound)) … \(mm(z.upperBound))")
        }
        let measures = scene.selectionMeasures
        if measures.count == 1, let measure = measures.first {
            switch measure.kind {
                case .line, .curve: parts.append("L \(mm(measure.length))")
                case .arc:          parts.append("R \(mm(measure.radius ?? 0))")
                case .circle:       parts.append("Ø \(mm((measure.radius ?? 0) * 2))")
            }
        } else if measures.count > 1 {
            parts.append("L \(mm(measures.reduce(Float(0)) { $0 + $1.length }))")
        }
        return parts.joined(separator: "  ·  ") + " mm"
    }
}

/// The callout of the selected STEP edges: the two actions, then one line of numbers.
private struct STEPSelectionCallout: View {

    let summary: String
    let canSelectLinked: Bool
    let canAdd: Bool
    let onSelectLinked: () -> Void
    let onAdd: () -> Void

    private static let arrowSize = CGSize(width: 16, height: 8)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onSelectLinked) {
                    Label("Select linked", systemImage: "square.dashed")
                }
                .buttonStyle(.bordered)
                .disabled(!canSelectLinked)
                .help(canSelectLinked
                      ? "Also select every edge connected to the selection that lies in the same plane"
                      : "Needs edges that lie in one plane: select a curve, or two edges that are not in line")
                Button(action: onAdd) {
                    Label("Add toolpath", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
            }
            .controlSize(.small)
            .fixedSize()

            Text(summary)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .help("Z: height relative to z0 (negative is below)  ·  Ø: diameter  ·  R: radius  ·  L: length")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8 + Self.arrowSize.height)
        .background {
            CalloutShape(arrowSize: Self.arrowSize)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .overlay {
            CalloutShape(arrowSize: Self.arrowSize)
                .stroke(.separator)
        }
    }
}

/// A rounded rectangle with a downward arrow centered on its bottom edge, as one
/// outline so the fill and the stroke have no seam where the arrow joins.
private struct CalloutShape: Shape {

    var cornerRadius: CGFloat = 10
    let arrowSize: CGSize

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let bottom = rect.maxY - arrowSize.height
        let midX = rect.midX

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom),
                 tangent2End: CGPoint(x: rect.maxX - r, y: bottom), radius: r)
        // The arrow
        p.addLine(to: CGPoint(x: midX + arrowSize.width / 2, y: bottom))
        p.addLine(to: CGPoint(x: midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: midX - arrowSize.width / 2, y: bottom))
        p.addLine(to: CGPoint(x: rect.minX + r, y: bottom))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom),
                 tangent2End: CGPoint(x: rect.minX, y: bottom - r), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.closeSubpath()
        return p
    }
}

/// Covers the canvas and keeps an "Add toolpath" tooltip on top of the selected
/// shapes, arrow pointing down at them. It follows the shapes through orbit, pan, zoom
/// and resize by re-reading the camera after every frame the canvas draws.
struct AddToolpathTooltipLayer: View {

    @ObservedObject var scene: CAMSceneModel
    let zoomModel: CanvasZoomModel
    let shapeCount: Int
    let onAdd: () -> Void

    /// Bumped after every frame so the body re-reads the camera. Only this
    /// small view is invalidated, not the CAM screen around it.
    @State private var frameTick = 0

    /// Space between the arrow tip and the top of the shape.
    private static let gap: CGFloat = 6
    /// Keeps the tooltip on screen when the shape is at (or above) the top
    /// edge: roughly its own height plus a margin.
    private static let minAnchorY: CGFloat = 56
    private static let horizontalMargin: CGFloat = 110

    var body: some View {
        let _ = frameTick
        GeometryReader { proxy in
            if shapeCount > 0, let anchor = anchor(in: proxy.size) {
                AddToolpathTooltip(shapeCount: shapeCount, onAdd: onAdd)
                    .fixedSize()
                    // Zero-size frame bottom-aligned on the anchor: the
                    // tooltip's arrow tip lands exactly on that point.
                    .frame(width: 0, height: 0, alignment: .bottom)
                    .position(anchor)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: shapeCount > 0)
        .onReceive(zoomModel.frameRendered.receive(on: DispatchQueue.main)) { _ in
            frameTick &+= 1
        }
    }

    /// Top-center of the selection's bounding box, in this view's points. The box lies flat at
    /// z = 0; under an orbited camera its highest corner on screen is what the arrow points at.
    private func anchor(in size: CGSize) -> CGPoint? {
        guard let bounds = scene.selectionWorldBounds, size.width > 0, size.height > 0 else {
            return nil
        }
        let corners = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                       CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)]
        let projected = corners.compactMap { zoomModel.normalizedViewPoint(forWorld: $0) }
        guard let top = projected.map(\.y).min(),
              let left = projected.map(\.x).min(),
              let right = projected.map(\.x).max() else {
            return nil
        }
        let margin = min(Self.horizontalMargin, size.width / 2)
        let x = min(max((left + right) / 2 * size.width, margin), size.width - margin)
        let y = max(top * size.height - Self.gap, Self.minAnchorY)
        return CGPoint(x: x, y: y)
    }
}

private struct AddToolpathTooltip: View {

    let shapeCount: Int
    var noun = "shape"
    let onAdd: () -> Void

    private static let arrowSize = CGSize(width: 16, height: 8)

    var body: some View {
        HStack(spacing: 12) {
            Text(shapeCount == 1 ? "1 \(noun) selected" : "\(shapeCount) \(noun)s selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(action: onAdd) {
                Label("Add toolpath", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8 + Self.arrowSize.height)
        .background {
            CalloutShape(arrowSize: Self.arrowSize)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .overlay {
            CalloutShape(arrowSize: Self.arrowSize)
                .stroke(.separator)
        }
    }
}
