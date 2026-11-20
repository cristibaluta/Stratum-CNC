//
//  STEP3DCanvas.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 11.11.2026.
//

import SwiftUI
import simd
import StratumCAM

/// The CAM scene plus every loaded STEP/STL file in one canvas, with edge picking next to shape
/// picking. All the files are drawn at once; which row is selected never hides another file.
struct STEP3DCanvas: View {

    /// Every file that has finished loading, in the order they were added.
    let scenes: [STEPDocumentScene]
    /// Fires when any of `scenes` changes (selection, visibility, display options), to repaint.
    @ObservedObject var sceneChanges: STEPSceneChanges
    let shapes: CAMSceneModel
    let sceneObjects: [RenderObject]
    let partTransform: simd_float4x4
    let previewTransform: simd_float4x4
    /// The active setup: its face is what the selected edges are projected onto, and measured to
    let projectionFrame: SetupFrame
    let clearColor: SIMD4<Float>
    let isDark: Bool
    let zoomModel: CanvasZoomModel
    let addToolpathShapeCount: Int
    let canAddToolpath: Bool
    let fitRequest: Int
    let onAddToolpath: () -> Void
    let onAddStepToolpath: (SC.MachiningOperation.Kind) -> Void
    let onEmptyClick: () -> Void
    var onEmptyDoubleClick: () -> Void = {}

    var body: some View {
        MetalCanvasView(objects: .constant(sceneObjects + scenes.flatMap(\.visibleObjects)),
                        clearColor: clearColor,
                        pointerHandler: shapes.interaction,
                        zoomModel: zoomModel,
                        onClick: { click in
                            CAM_Metal_View.route(click,
                                                 shapes: shapes.interaction,
                                                 steps: scenes,
                                                 onEmptyClick: onEmptyClick,
                                                 onEmptyDoubleClick: onEmptyDoubleClick)
                        },
                        partTransform: partTransform,
                        previewTransform: previewTransform,
                        adaptiveModelFit: true,
                        // Frames everything again when a file is added or removed, or one asks for it
                        fitRequest: scenes.reduce(0) { $0 &+ $1.fitRequest } &+ scenes.count &+ fitRequest)
            .onAppear { syncSceneSettings() }
            .onChange(of: isDark) { _, _ in syncSceneSettings() }
            // The projection lands on the setup's z0: the part's underside when flipped, a side of
            // the stock for the front, back, left and right setups
            .onChange(of: projectionFrame, initial: true) { _, _ in syncSceneSettings() }
            // A file that has just loaded gets the same appearance and projection as the others
            .onChange(of: scenes.map { ObjectIdentifier($0) }) { _, _ in syncSceneSettings() }
            .overlay {
                AddToolpathTooltipLayer(scene: shapes,
                                        zoomModel: zoomModel,
                                        shapeCount: addToolpathShapeCount,
                                        onAdd: onAddToolpath)
            }
            .overlay {
                // No callout while a toolpath is open (its details panel is showing)
                if canAddToolpath {
                    // Only the file with selected edges shows its callout
                    ForEach(scenes) { scene in
                        STEPAddToolpathTooltipLayer(scene: scene,
                                                    zoomModel: zoomModel,
                                                    canAdd: canAddToolpath,
                                                    onChoose: onAddStepToolpath)
                    }
                }
            }
    }

    private func syncSceneSettings() {
        for scene in scenes {
            scene.setAppearance(isDark: isDark)
            scene.setProjectionFrame(projectionFrame)
        }
    }
}
