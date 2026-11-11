//
//  AddToolpathTooltipLayer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 11.11.2026.
//

import SwiftUI

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
