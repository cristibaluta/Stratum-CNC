//
//  CAM_Metal_View.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
import SwiftUI
import AppKit
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
    /// The STEP model selected in the objects list, if it is the one on the canvas. It gets a box
    /// and a handle like a selected shape, and dragging the handle moves it.
    let selectedStepModelID: UUID?
    /// The model was dragged by this much (canvas mm).
    let onMoveStepModel: (UUID, CGFloat, CGFloat) -> Void
    /// A click on empty canvas: the selected STEP model is deselected, like a selected shape.
    let onDeselectStepModel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(canvasState: D2_CanvasState,
         zoomModel: CanvasZoomModel,
         stepScene: STEPDocumentScene? = nil,
         startsTopDown: Bool = true,
         partFrame: SetupFrame = .identity,
         addToolpathShapeCount: Int = 0,
         canAddToolpathFromEdges: Bool = false,
         fitRequest: Int = 0,
         selectedStepModelID: UUID? = nil,
         onMoveStepModel: @escaping (UUID, CGFloat, CGFloat) -> Void = { _, _, _ in },
         onDeselectStepModel: @escaping () -> Void = {},
         onAddToolpath: @escaping () -> Void = {}) {
        _scene = StateObject(wrappedValue: CAMSceneModel(canvasState: canvasState))
        self.zoomModel = zoomModel
        self.stepScene = stepScene
        self.startsTopDown = startsTopDown
        self.partFrame = partFrame
        self.addToolpathShapeCount = addToolpathShapeCount
        self.canAddToolpathFromEdges = canAddToolpathFromEdges
        self.fitRequest = fitRequest
        self.selectedStepModelID = selectedStepModelID
        self.onMoveStepModel = onMoveStepModel
        self.onDeselectStepModel = onDeselectStepModel
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
            .onAppear {
                scene.interaction.onStepModelMoved = onMoveStepModel
            }
            // The handle the mouse can grab follows the selected model, wherever it is moved to
            .onChange(of: stepFootprint?.origin, initial: true) { _, _ in syncStepModelHandle() }
            .onChange(of: stepFootprint?.size) { _, _ in syncStepModelHandle() }
            .onChange(of: selectedStepModelID) { _, _ in syncStepModelHandle() }
    }

    /// Where the selected STEP model's footprint is on the canvas (its corner and size, in mm),
    /// or `nil` when it isn't the one drawn, isn't selected or is hidden.
    private var stepFootprint: (origin: SIMD2<Float>, size: SIMD2<Float>)? {
        guard let stepScene, selectedStepModelID == stepScene.id, stepScene.isModelVisible,
              let size = stepScene.content.size else {
            return nil
        }
        return (SIMD2<Float>(stepScene.offset.x, stepScene.offset.y), SIMD2<Float>(size.x, size.y))
    }

    private func syncStepModelHandle() {
        if let stepScene, let footprint = stepFootprint {
            let center = footprint.origin + footprint.size / 2
            scene.interaction.stepModelHandle = (stepScene.id, CGPoint(x: CGFloat(center.x), y: CGFloat(center.y)))
        } else {
            scene.interaction.stepModelHandle = nil
        }
    }

    /// The box and the handle of the selected STEP model, as flat overlay like a selected shape's.
    private var stepModelOverlay: [RenderObject] {
        guard let footprint = stepFootprint else {
            return []
        }
        var objects: [RenderObject] = []
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            objects = CAMSelectionOverlay.renderObjects(forSTEPModelAt: footprint.origin,
                                                        size: footprint.size,
                                                        boxColor: CAMSceneModel.rgba(NSColor.systemRed),
                                                        handleColor: CAMSceneModel.rgba(NSColor.systemOrange))
        }
        return objects
    }

    /// The CAM scene (shapes, toolpaths, stock, selection overlays; the ruler on the stock's
    /// bottom face and the XYZ origin axes — see `CAMSceneModel.renderObjects3D`), plus the STEP
    /// wireframe when there is one. A different branch for STEP means a fresh `MetalCanvasView`
    /// (the camera starts over, at the orbited view). `scene` lives in this view, so nothing is lost.
    @ViewBuilder
    private var canvas: some View {
        if let stepScene {
            STEP3DCanvas(scene: stepScene, shapes: scene,
                         sceneObjects: scene.renderObjects3D(frame: partFrame) + stepModelOverlay,
                         partTransform: partFrame.matrix,
                         previewTransform: partFrame.previewMatrix,
                         clearColor: scene.backgroundColor, isDark: colorScheme == .dark,
                         zoomModel: zoomModel,
                         addToolpathShapeCount: addToolpathShapeCount,
                         canAddToolpath: canAddToolpathFromEdges,
                         fitRequest: fitRequest,
                         onAddToolpath: onAddToolpath,
                         onEmptyClick: onDeselectStepModel)
        } else {
            MetalCanvasView(objects: .constant(scene.renderObjects3D(frame: partFrame)),
                            clearColor: scene.backgroundColor,
                            pointerHandler: scene.interaction,
                            zoomModel: zoomModel,
                            onClick: { click in
                                Self.route(click, shapes: scene.interaction, step: nil,
                                           onEmptyClick: onDeselectStepModel)
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
    static func route(_ click: CanvasClick, shapes: CAMCanvasInteraction, step: STEPDocumentScene?,
                      onEmptyClick: () -> Void = {}) {
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
        onEmptyClick()
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
    let onEmptyClick: () -> Void

    var body: some View {
        MetalCanvasView(objects: .constant(sceneObjects + scene.visibleObjects),
                        clearColor: clearColor,
                        pointerHandler: shapes.interaction,
                        zoomModel: zoomModel,
                        onClick: { click in
                            CAM_Metal_View.route(click, shapes: shapes.interaction, step: scene,
                                                 onEmptyClick: onEmptyClick)
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
    /// Whether the details (distance to z0, size of the edges) are open. Remembered.
    @AppStorage("STEPSelectionDetailsExpanded") private var detailsExpanded = true

    private static let gap: CGFloat = 6
    private static let minAnchorY: CGFloat = 56
    private static let horizontalMargin: CGFloat = 110
    private static let detailRowHeight: CGFloat = 18

    var body: some View {
        let _ = frameTick
        GeometryReader { proxy in
            let count = scene.selectedEdges.count
            let details = Self.details(for: scene)
            // The callout grows upward, so an open one needs more room above its anchor.
            let minY = Self.minAnchorY + (details.isEmpty ? 0
                : 24 + (detailsExpanded ? CGFloat(details.count) * Self.detailRowHeight + 8 : 0))
            if count > 0, let anchor = anchor(in: proxy.size, minY: minY) {
                AddToolpathTooltip(shapeCount: count, noun: "edge", onAdd: onAdd,
                                   onSelectLinked: scene.canSelectLinkedInPlane
                                       ? { scene.selectLinkedEdgesInPlane() } : nil,
                                   details: details, detailsExpanded: $detailsExpanded)
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
    private func anchor(in size: CGSize, minY: CGFloat) -> CGPoint? {
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
        let y = max(top * size.height - Self.gap, minY)
        return CGPoint(x: x, y: y)
    }

    /// How far the selection is from z0, and the size of each selected edge: length of a line,
    /// radius of an arc, diameter of a circle. A long selection lists the first few.
    private static func details(for scene: STEPDocumentScene) -> [TooltipDetail] {
        var rows: [TooltipDetail] = []
        if let z = scene.selectionZRange {
            func mm(_ value: Float) -> String { String(format: "%.3f", value) }
            if z.upperBound - z.lowerBound < 1e-3 {
                let value = z.lowerBound
                rows.append(TooltipDetail(label: "Distance to z0",
                                          value: abs(value) < 1e-3 ? "0 mm (on z0)"
                                              : "\(mm(abs(value))) mm \(value < 0 ? "below" : "above")"))
            } else {
                rows.append(TooltipDetail(label: "Z from z0", value: "\(mm(z.lowerBound)) … \(mm(z.upperBound)) mm"))
            }
        }
        let measures = scene.selectionMeasures
        for measure in measures.prefix(4) {
            rows.append(TooltipDetail(label: measure.label, value: measure.valueText))
        }
        if measures.count > 4 {
            rows.append(TooltipDetail(label: "+\(measures.count - 4) more edges", value: ""))
        }
        return rows
    }
}

private extension STEPDisplayGeometry.EdgeMeasure {
    var label: String {
        switch kind {
            case .line: return "Line length"
            case .arc: return "Arc radius"
            case .circle: return "Circle diameter"
            case .curve: return "Curve length"
        }
    }

    var valueText: String {
        switch kind {
            case .line, .curve: return String(format: "%.3f mm", length)
            case .arc: return String(format: "%.3f mm", radius ?? 0)
            case .circle: return String(format: "%.3f mm", (radius ?? 0) * 2)
        }
    }
}

/// A line of the callout's details: what it is and its value.
private struct TooltipDetail: Hashable {
    let label: String
    let value: String
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
    /// When set, a secondary button next to "Add toolpath" (STEP edges: select the connected
    /// edges in the same plane).
    var onSelectLinked: (() -> Void)? = nil
    /// Lines shown under the buttons, folded away with the chevron. Empty: none, and no chevron.
    fileprivate var details: [TooltipDetail] = []
    fileprivate var detailsExpanded: Binding<Bool>? = nil

    private static let arrowSize = CGSize(width: 16, height: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actions
            if !details.isEmpty, let expanded = detailsExpanded {
                Divider()
                detailsSection(expanded: expanded)
            }
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

    private func detailsSection(expanded: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 10)
                    Text("Details").font(.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded.wrappedValue {
                ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                    HStack(spacing: 16) {
                        Text(detail.label).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(detail.value).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Text(shapeCount == 1 ? "1 \(noun) selected" : "\(shapeCount) \(noun)s selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let onSelectLinked {
                Button(action: onSelectLinked) {
                    Label("Select linked", systemImage: "square.dashed")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Also select every edge connected to the selection that lies in the same plane")
            }
            Button(action: onAdd) {
                Label("Add toolpath", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
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
