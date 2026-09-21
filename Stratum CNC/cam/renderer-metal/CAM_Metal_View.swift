//
//  CAM_Metal_View.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  Metal-backed replacement for `CAM_2D_View`. As of step 6, this is the
//  only CAM canvas — `CAM_2D_View` and its CoreAnimation stack
//  (`D2_CanvasNSView`, `D2_CanvasRenderer`, `D2_ObjectNode`, `StockLayer`,
//  `RulerShapeLayer`, `CenterShapeLayer`) were deleted, and the
//  `CAMFeatureFlags.metalCanvasKey` toggle that switched between them is
//  gone too. Same data source (`D2_CanvasState`), same slot in `CAMView`.
//
//  What it does today: draws shapes (selection/picking colors included),
//  the toolpath preview, the ruler and the stock; pan (drag or scroll) and
//  pinch-zoom via `MetalCanvasView`'s `.locked2D` mode; and, through
//  `CAMCanvasInteraction`, click / Shift-Cmd multi-select, "select shapes"
//  picking, and drag-to-move by the rotation-center handle (step 4).
//
//  Known gap carried over from before the swap (step 5 QA pass covered the
//  rest): no viewport persistence. The saved viewport (`CAMModel.savedViewport`
//  / `saveViewport`) is in CoreAnimation pan/zoom units, meaningless to a
//  `Camera` target/distance, so this view still ignores it — the canvas
//  re-fits on load instead of restoring the last session's framing.
//

import SwiftUI

@MainActor
struct CAM_Metal_View: View {

    @StateObject private var scene: CAMSceneModel
    @Environment(\.colorScheme) private var colorScheme

    init(canvasState: D2_CanvasState) {
        _scene = StateObject(wrappedValue: CAMSceneModel(canvasState: canvasState))
    }

    var body: some View {
        MetalCanvasView(objects: .constant(scene.renderObjects),
                        interactionMode: .locked2D,
                        clearColor: scene.backgroundColor,
                        pointerHandler: scene.interaction)
            .onAppear {
                scene.setColorScheme(colorScheme)
            }
            .onChange(of: colorScheme) { _, newScheme in
                scene.setColorScheme(newScheme)
            }
    }
}
