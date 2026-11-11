//
//  STEP3DCanvas.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 11.11.2026.
//

import SwiftUI
import simd
import StratumCAM

/// The CAM scene plus the STEP wireframe in one canvas, with edge picking next to shape picking.
struct STEP3DCanvas: View {

    @ObservedObject var scene: STEPDocumentScene
    let shapes: CAMSceneModel
    let sceneObjects: [RenderObject]
    let partTransform: simd_float4x4
    let previewTransform: simd_float4x4
    /// Part-frame height of the active setup's z0 (`SetupFrame.z0InPartFrame`)
    let projectionZ: Float
    let clearColor: SIMD4<Float>
    let isDark: Bool
    let zoomModel: CanvasZoomModel
    let addToolpathShapeCount: Int
    let canAddToolpath: Bool
    let fitRequest: Int
    let onAddToolpath: () -> Void
    let onAddStepToolpath: (SC.MachiningOperation.Kind) -> Void
    let onEmptyClick: () -> Void

    var body: some View {
        MetalCanvasView(objects: .constant(sceneObjects + scene.visibleObjects),
                        clearColor: clearColor,
                        pointerHandler: shapes.interaction,
                        zoomModel: zoomModel,
                        onClick: { click in
                            CAM_Metal_View.route(click,
                                                 shapes: shapes.interaction,
                                                 step: scene,
                                                 onEmptyClick: onEmptyClick)
                        },
                        partTransform: partTransform,
                        previewTransform: previewTransform,
                        adaptiveModelFit: true,
                        fitRequest: scene.fitRequest &+ fitRequest)
            .id(ObjectIdentifier(scene))
            .onAppear {
                scene.setAppearance(isDark: isDark)
            }
            .onChange(of: isDark) { _, dark in
                scene.setAppearance(isDark: dark)
            }
            // The projection lands on the setup's z0, which is the part's underside when flipped
            .onChange(of: projectionZ, initial: true) { _, z in
                scene.setProjectionZ(z)
            }
            .overlay {
                AddToolpathTooltipLayer(scene: shapes,
                                        zoomModel: zoomModel,
                                        shapeCount: addToolpathShapeCount,
                                        onAdd: onAddToolpath)
            }
            .overlay {
                // No callout while a toolpath is open (its details panel is showing)
                if canAddToolpath {
                    STEPAddToolpathTooltipLayer(scene: scene,
                                                zoomModel: zoomModel,
                                                canAdd: canAddToolpath,
                                                onChoose: onAddStepToolpath)
                }
            }
    }
}
