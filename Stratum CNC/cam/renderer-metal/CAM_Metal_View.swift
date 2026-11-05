//
//  CAM_Metal_View.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
import SwiftUI
import simd

/// The CAM canvas: one free 3D camera (orbit, pan, zoom and the orientation cube from
/// `CanvasInputSettings`) over the whole scene — the stock, the shapes (flat, at z = 0), the
/// toolpaths and, when there is one, the STEP wireframe. Shapes and STEP edges are both selectable.
@MainActor
struct CAM_Metal_View: View {

    @StateObject private var scene: CAMSceneModel
    let zoomModel: CanvasZoomModel
    /// The STEP scene drawn with the shapes. `nil` without a STEP model, or while it is still
    /// loading or failed to load.
    let stepScene: STEPDocumentScene?
    /// Flat work only (no STEP model): the camera starts straight above, as a 2D view would.
    /// With a STEP model it starts at the orbited 3D view instead. Only read when the canvas is created.
    let startsTopDown: Bool
    /// The active setup's map: the canvas turns the stock and model with it so that setup's
    /// face is the one facing up, with the origin where it was.
    let partFrame: SetupFrame
    /// How many shapes an "Add toolpath" tooltip would use; 0 hides the tooltip.
    /// The owner decides when it is allowed (e.g. not while a toolpath is open).
    let addToolpathShapeCount: Int
    /// The selected STEP edges can become a toolpath (false while a toolpath is open).
    let canAddToolpathFromEdges: Bool
    /// Bumped by the owner to frame the whole scene again.
    let fitRequest: Int
    let onAddToolpath: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(canvasState: D2_CanvasState,
         zoomModel: CanvasZoomModel,
         stepScene: STEPDocumentScene? = nil,
         startsTopDown: Bool = true,
         partFrame: SetupFrame = .identity,
         addToolpathShapeCount: Int = 0,
         canAddToolpathFromEdges: Bool = false,
         fitRequest: Int = 0,
         onAddToolpath: @escaping () -> Void = {}) {
        _scene = StateObject(wrappedValue: CAMSceneModel(canvasState: canvasState))
        self.zoomModel = zoomModel
        self.stepScene = stepScene
        self.startsTopDown = startsTopDown
        self.partFrame = partFrame
        self.addToolpathShapeCount = addToolpathShapeCount
        self.canAddToolpathFromEdges = canAddToolpathFromEdges
        self.fitRequest = fitRequest
        self.onAddToolpath = onAddToolpath
    }

    var body: some View {
        canvas
            .onAppear {
                scene.setColorScheme(colorScheme)
            }
            .onChange(of: colorScheme) { _, newScheme in
                scene.setColorScheme(newScheme)
            }
    }

    /// The CAM scene (shapes, toolpaths, stock, selection overlays; the ruler on the stock's
    /// bottom face and the XYZ origin axes — see `CAMSceneModel.renderObjects3D`), plus the STEP
    /// wireframe when there is one. A different branch for STEP means a fresh `MetalCanvasView`
    /// (the camera starts over, at the orbited view). `scene` lives in this view, so nothing is lost.
    @ViewBuilder
    private var canvas: some View {
        if let stepScene {
            STEP3DCanvas(scene: stepScene, shapes: scene, sceneObjects: scene.renderObjects3D(frame: partFrame),
                         partTransform: partFrame.matrix,
                         previewTransform: partFrame.previewMatrix,
                         clearColor: scene.backgroundColor, isDark: colorScheme == .dark,
                         zoomModel: zoomModel,
                         addToolpathShapeCount: addToolpathShapeCount,
                         canAddToolpath: canAddToolpathFromEdges,
                         fitRequest: fitRequest,
                         onAddToolpath: onAddToolpath)
        } else {
            MetalCanvasView(objects: .constant(scene.renderObjects3D(frame: partFrame)),
                            clearColor: scene.backgroundColor,
                            pointerHandler: scene.interaction,
                            zoomModel: zoomModel,
                            onClick: { click in
                                Self.route(click, shapes: scene.interaction, step: nil)
                            },
                            partTransform: partFrame.matrix,
                            previewTransform: partFrame.previewMatrix,
                            startsTopDown: startsTopDown,
                            adaptiveModelFit: true,
                            fitRequest: fitRequest)
                .overlay {
                    AddToolpathTooltipLayer(scene: scene,
                                            zoomModel: zoomModel,
                                            shapeCount: addToolpathShapeCount,
                                            onAdd: onAddToolpath)
                }
        }
    }

    /// Resolves a click on the canvas: a flat shape wins (it lies on the stock's top face, in
    /// front of the model's edges), then a STEP edge, then empty space. Shapes and edges are never
    /// selected together, except as the picks of an open toolpath.
    static func route(_ click: CanvasClick, shapes: CAMCanvasInteraction, step: STEPDocumentScene?) {
        let extend = click.extendsSelection
        let picking = shapes.isPicking

        if let pointer = click.pointer, let hit = shapes.shapeHit(at: pointer) {
            shapes.select(hit, extend: extend)
            if !picking { step?.clearSelection() }
            return
        }
        if let step, let edge = step.edge(at: click.viewPoint, viewport: click.viewSize, matrix: click.matrix) {
            step.select(edge, extend: extend)
            if !picking { shapes.clearSelection() }
            return
        }
        // Empty space: keeps a toolpath's picks, and a multi-select's selection
        guard !picking, !extend else {
            return
        }
        shapes.select(nil, extend: false)
        step?.clearSelection()
    }
}

/// The CAM scene plus the STEP wireframe in one canvas, with edge picking next to shape picking.
private struct STEP3DCanvas: View {

    @ObservedObject var scene: STEPDocumentScene
    let shapes: CAMSceneModel
    let sceneObjects: [RenderObject]
    let partTransform: simd_float4x4
    let previewTransform: simd_float4x4
    let clearColor: SIMD4<Float>
    let isDark: Bool
    let zoomModel: CanvasZoomModel
    let addToolpathShapeCount: Int
    let canAddToolpath: Bool
    let fitRequest: Int
    let onAddToolpath: () -> Void

    var body: some View {
        MetalCanvasView(objects: .constant(sceneObjects + scene.visibleObjects),
                        clearColor: clearColor,
                        pointerHandler: shapes.interaction,
                        zoomModel: zoomModel,
                        onClick: { click in
                            CAM_Metal_View.route(click, shapes: shapes.interaction, step: scene)
                        },
                        partTransform: partTransform,
                        previewTransform: previewTransform,
                        adaptiveModelFit: true,
                        fitRequest: scene.fitRequest &+ fitRequest)
            .id(ObjectIdentifier(scene))
            .onAppear { scene.setAppearance(isDark: isDark) }
            .onChange(of: isDark) { _, dark in scene.setAppearance(isDark: dark) }
            .overlay {
                AddToolpathTooltipLayer(scene: shapes,
                                        zoomModel: zoomModel,
                                        shapeCount: addToolpathShapeCount,
                                        onAdd: onAddToolpath)
            }
            .overlay {
                if canAddToolpath {
                    STEPAddToolpathTooltipLayer(scene: scene, zoomModel: zoomModel, onAdd: onAddToolpath)
                }
            }
    }
}

/// The "Add toolpath" tooltip over the selected STEP edges. It follows the
/// selection's top as the camera orbits, pans and zooms.
private struct STEPAddToolpathTooltipLayer: View {

    @ObservedObject var scene: STEPDocumentScene
    let zoomModel: CanvasZoomModel
    let onAdd: () -> Void

    @State private var frameTick = 0

    private static let gap: CGFloat = 6
    private static let minAnchorY: CGFloat = 56
    private static let horizontalMargin: CGFloat = 110

    var body: some View {
        let _ = frameTick
        GeometryReader { proxy in
            let count = scene.selectedEdges.count
            if count > 0, let anchor = anchor(in: proxy.size) {
                AddToolpathTooltip(shapeCount: count, noun: "edge", onAdd: onAdd)
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
}

/// Covers the canvas and keeps an "Add toolpath" tooltip on top of the selected
/// shapes, arrow pointing down at them. It follows the shapes through orbit, pan, zoom
/// and resize by re-reading the camera after every frame the canvas draws.
private struct AddToolpathTooltipLayer: View {

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
