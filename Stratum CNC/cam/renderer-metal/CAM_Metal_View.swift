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
                STEPAddToolpathTooltipLayer(scene: scene, zoomModel: zoomModel,
                                            canAdd: canAddToolpath, onAdd: onAddToolpath)
            }
    }
}
