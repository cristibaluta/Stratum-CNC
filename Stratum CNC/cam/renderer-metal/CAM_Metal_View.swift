//
//  CAM_Metal_View.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  Metal-backed replacement for `CAM_2D_View`, shipped behind a flag while
//  `CAM_2D_View` keeps shipping unchanged (step 3 of the plan in
//  metal-canvas-for-cam-plan.md). Same data source (`D2_CanvasState`), same
//  slot in `CAMView` — only the render backend differs.
//
//  What it does today: draws shapes (selection/picking colors included),
//  the toolpath preview, the ruler and the stock; pan (drag or scroll) and
//  pinch-zoom via `MetalCanvasView`'s `.locked2D` mode; and, through
//  `CAMCanvasInteraction`, click / Shift-Cmd multi-select, "select shapes"
//  picking, and drag-to-move by the rotation-center handle (step 4).
//
//  What it does NOT do yet (each is a later step, on purpose):
//    - stock fill tint / hatch, filled handle dot, true-to-life 1 mm : 1 pt
//      zoom → step 5 (QA)
//    - viewport persistence (`initialViewport` / `onViewportChanged`): the
//      saved viewport is CoreAnimation pan/zoom units, meaningless to a
//      `Camera` target/distance, so the Metal path ignores it for now.
//

import SwiftUI

/// Flags for the CAM canvas migration. Plain `UserDefaults` so it can also
/// be flipped from Terminal: `defaults write <bundle id> cam.useMetalCanvas -bool YES`.
enum CAMFeatureFlags {
    static let metalCanvasKey = "cam.useMetalCanvas"
}

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
