//
//  CAM_Metal_View.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
import SwiftUI
import simd
import SwiftSTEP
import StratumCAM

/// The CAM canvas: one free 3D camera (orbit, pan, zoom and the orientation cube from
/// `CanvasInputSettings`) over the whole scene — the stock, the shapes (flat, at z = 0), the
/// toolpaths and, when there is one, the STEP wireframe. Shapes and STEP edges are both selectable.
@MainActor
struct CAM_Metal_View: View {

    @StateObject private var scene: CAMSceneModel
    /// Turns the stock and model over when the active setup's face changes.
    @StateObject private var flip: SetupFlipAnimator
    let zoomModel: CanvasZoomModel
    /// The imported STEP/STL files. Every one that has finished loading is drawn with the shapes,
    /// all at once; there is no STEP layer on the canvas until the first one has.
    @ObservedObject var stepWorkspace: STEPWorkspace
    /// Flat work only (no STEP model): the camera starts straight above, as a 2D view would.
    /// With a STEP model it starts at the orbited 3D view instead. Only read when the canvas is created.
    let startsTopDown: Bool
    /// The active setup's map: the canvas turns the stock and model with it so that setup's
    /// face is the one facing up, with the origin where it was.
    let partFrame: SetupFrame
    /// How many shapes an "Add toolpath" tooltip would use; 0 hides the tooltip.
    /// The owner decides when it is allowed (e.g. not while a toolpath is open).
    let addToolpathShapeCount: Int
    /// The selected STEP edges can become a toolpath (false while a toolpath is open, which
    /// also hides their callout).
    let canAddToolpathFromEdges: Bool
    /// Bumped by the owner to frame the whole scene again.
    let fitRequest: Int
    let onAddToolpath: () -> Void
    /// An operation was picked in the STEP edges' "Add toolpath" list.
    let onAddStepToolpath: (SC.MachiningOperation.Kind) -> Void
    /// The STEP model selected in the objects list. It gets a box
    /// and a handle like a selected shape, and dragging the handle moves it.
    let selectedStepModelID: UUID?
    /// The body, in its file's scene, that row stands for; `nil` when no body is selected.
    let selectedStepBody: STEP.BodyID?
    /// The model was dragged by this much (canvas mm).
    let onMoveStepModel: (UUID, CGFloat, CGFloat) -> Void
    /// A click on empty canvas: the selected STEP model is deselected, like a selected shape.
    let onDeselectStepModel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(canvasState: D2_CanvasState,
         zoomModel: CanvasZoomModel,
         stepWorkspace: STEPWorkspace,
         startsTopDown: Bool = true,
         partFrame: SetupFrame = .identity,
         addToolpathShapeCount: Int = 0,
         canAddToolpathFromEdges: Bool = false,
         fitRequest: Int = 0,
         selectedStepModelID: UUID? = nil,
         selectedStepBody: STEP.BodyID? = nil,
         onMoveStepModel: @escaping (UUID, CGFloat, CGFloat) -> Void = { _, _, _ in },
         onDeselectStepModel: @escaping () -> Void = {},
         onAddToolpath: @escaping () -> Void = {},
         onAddStepToolpath: @escaping (SC.MachiningOperation.Kind) -> Void = { _ in }) {

        _scene = StateObject(wrappedValue: CAMSceneModel(canvasState: canvasState))
        _flip = StateObject(wrappedValue: SetupFlipAnimator(initial: partFrame))

        self.zoomModel = zoomModel
        _stepWorkspace = ObservedObject(wrappedValue: stepWorkspace)
        self.startsTopDown = startsTopDown
        self.partFrame = partFrame
        self.addToolpathShapeCount = addToolpathShapeCount
        self.canAddToolpathFromEdges = canAddToolpathFromEdges
        self.fitRequest = fitRequest
        self.selectedStepModelID = selectedStepModelID
        self.selectedStepBody = selectedStepBody
        self.onMoveStepModel = onMoveStepModel
        self.onDeselectStepModel = onDeselectStepModel
        self.onAddToolpath = onAddToolpath
        self.onAddStepToolpath = onAddStepToolpath
    }

    var body: some View {
        canvas
            .onAppear {
                scene.setColorScheme(colorScheme)
            }
            .onChange(of: colorScheme) { _, newScheme in
                scene.setColorScheme(newScheme)
            }
            .onChange(of: partFrame) { _, newFrame in
                flip.start(to: newFrame)
            }
            .onAppear {
                scene.interaction.onStepModelMoved = onMoveStepModel
            }
            // The handle the mouse can grab follows the selected model, wherever it is moved to
            .onChange(of: stepFootprint?.origin, initial: true) { _, _ in syncStepModelHandle() }
            .onChange(of: stepFootprint?.size) { _, _ in syncStepModelHandle() }
            .onChange(of: selectedStepModelID) { _, _ in syncStepModelHandle() }
            .onChange(of: selectedStepBody) { _, _ in syncStepModelHandle() }
    }

    /// Where the selected STEP model's footprint is on the canvas (its corner and size, in mm),
    /// or `nil` when it isn't the one drawn, isn't selected or is hidden.
    private var stepFootprint: (origin: SIMD2<Float>, size: SIMD2<Float>)? {
        guard let modelID = selectedStepModelID, let body = selectedStepBody,
              let stepScene = stepWorkspace.scene(ofModel: modelID),
              stepScene.isBodyVisible(body), let size = stepScene.content.size(of: body) else {
            return nil
        }
        let position = stepScene.position(of: body)
        return (SIMD2<Float>(position.x, position.y), SIMD2<Float>(size.x, size.y))
    }

    private func syncStepModelHandle() {
        if let selectedStepModelID, let footprint = stepFootprint {
            let center = footprint.origin + footprint.size / 2
            scene.interaction.stepModelHandle = (selectedStepModelID, CGPoint(x: CGFloat(center.x), y: CGFloat(center.y)))
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
        STAppearance.perform(as: colorScheme) {
            objects = CAMSelectionOverlay.renderObjects(forSTEPModelAt: footprint.origin,
                                                        size: footprint.size,
                                                        boxColor: CAMSceneModel.rgba(STColor.systemRed),
                                                        handleColor: CAMSceneModel.rgba(STColor.systemOrange))
        }
        return objects
    }

    /// The matrix the stock and model are drawn with: the active setup's, or part-way to it while flipping.
    private var partMatrix: simd_float4x4 {
        flip.displayMatrix(for: partFrame)
    }

    /// The scene's objects for the 3D view. The flat shapes and toolpath overlay lie on the face
    /// that is up, so they sit out the flip and come back when the new face has landed.
    private var sceneObjects3D: [RenderObject] {
        let objects = scene.renderObjects3D(frame: partFrame)
        return flip.isFlipping(to: partFrame) ? objects.filter { $0.role != .faceOverlay } : objects
    }

    /// The CAM scene (shapes, toolpaths, stock, selection overlays; the ruler on the stock's
    /// bottom face and the XYZ origin axes — see `CAMSceneModel.renderObjects3D`), plus the STEP
    /// wireframe of every loaded STEP/STL file. The first file to load switches to another branch,
    /// hence a fresh `MetalCanvasView` (the camera starts over, at the orbited view); later files
    /// stay in the same canvas. `scene` lives in this view, so nothing is lost.
    @ViewBuilder
    private var canvas: some View {
        let stepScenes = stepWorkspace.loadedScenes
        if !stepScenes.isEmpty {
            STEP3DCanvas(scenes: stepScenes, sceneChanges: stepWorkspace.sceneChanges, shapes: scene,
                         sceneObjects: sceneObjects3D + stepModelOverlay,
                         partTransform: partMatrix,
                         previewTransform: partFrame.previewMatrix,
                         projectionZ: Float(partFrame.z0InPartFrame),
                         clearColor: scene.backgroundColor, isDark: colorScheme == .dark,
                         zoomModel: zoomModel,
                         addToolpathShapeCount: addToolpathShapeCount,
                         canAddToolpath: canAddToolpathFromEdges,
                         fitRequest: fitRequest,
                         onAddToolpath: onAddToolpath,
                         onAddStepToolpath: onAddStepToolpath,
                         onEmptyClick: onDeselectStepModel)
        } else {
            MetalCanvasView(objects: .constant(sceneObjects3D),
                            clearColor: scene.backgroundColor,
                            pointerHandler: scene.interaction,
                            zoomModel: zoomModel,
                            onClick: { click in
                                Self.route(click, shapes: scene.interaction, steps: [], onEmptyClick: onDeselectStepModel)
                            },
                            partTransform: partMatrix,
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
    /// front of the model's edges), then a STEP edge, then a flat face of the shaded model (its
    /// edges), then empty space. Shapes and edges are never
    /// selected together, except as the picks of an open toolpath.
    /// With several files on the canvas (`steps`), the nearest chamfer or face wins across all of
    /// them, and a pick selects in the file it landed on and clears the selection in the others
    /// (an open toolpath keeps collecting picks from every file).
    /// A double click on a STEP edge also expands the selection (see `expandSelection(from:)`).
    static func route(_ click: CanvasClick,
                      shapes: CAMCanvasInteraction,
                      steps: [STEPDocumentScene],
                      onEmptyClick: () -> Void = {}) {

        let extend = click.extendsSelection
        let picking = shapes.isPicking

        func clearSteps(except keep: STEPDocumentScene? = nil) {
            for other in steps where other !== keep && !other.selectedEdges.isEmpty {
                other.clearSelection()
            }
        }

        /// The face (or chamfer) under the cursor that is nearest to the viewer, over all files
        func nearestFace(chamfersOnly: Bool) -> (scene: STEPDocumentScene, edges: Set<STEP.EdgeID>)? {
            var best: (scene: STEPDocumentScene, edges: Set<STEP.EdgeID>, depth: Float)?
            for step in steps {
                guard let hit = step.faceHit(at: click.viewPoint, viewport: click.viewSize,
                                             matrix: click.matrix, chamfersOnly: chamfersOnly) else {
                    continue
                }
                if best == nil || hit.depth < best!.depth {
                    best = (step, hit.edges, hit.depth)
                }
            }
            return best.map { ($0.scene, $0.edges) }
        }

        if let pointer = click.pointer, let hit = shapes.shapeHit(at: pointer) {
            shapes.select(hit, extend: extend)
            if !picking {
                clearSteps()
            }
            return
        }
        // A chamfer before the edges: it is so thin that a click on it is always near one of its rails
        if let (step, edges) = nearestFace(chamfersOnly: true) {
            step.selectFace(edges, extend: extend)
            if !picking {
                shapes.clearSelection()
                clearSteps(except: step)
            }
            return
        }
        for step in steps {
            guard let edge = step.edge(at: click.viewPoint, viewport: click.viewSize, matrix: click.matrix) else {
                continue
            }
            if click.isDoubleClick, !extend {
                // Shortcut for the tooltip's "Select linked" / "Select similar"
                step.expandSelection(from: edge)
            } else {
                step.select(edge, extend: extend)
            }
            if !picking {
                shapes.clearSelection()
                clearSteps(except: step)
            }
            return
        }
        if let (step, edges) = nearestFace(chamfersOnly: false) {
            step.selectFace(edges, extend: extend)
            if !picking {
                shapes.clearSelection()
                clearSteps(except: step)
            }
            return
        }
        // Empty space: keeps a toolpath's picks, and a multi-select's selection
        guard !picking, !extend else {
            return
        }
        shapes.select(nil, extend: false)
        clearSteps()

        onEmptyClick()
    }
}
