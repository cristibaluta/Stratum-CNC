//
//  CAM_Metal_View.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
import SwiftUI

@MainActor
struct CAM_Metal_View: View {

    @StateObject private var scene: CAMSceneModel
    let zoomModel: CanvasZoomModel
    @Environment(\.colorScheme) private var colorScheme

    init(canvasState: D2_CanvasState, zoomModel: CanvasZoomModel) {
        _scene = StateObject(wrappedValue: CAMSceneModel(canvasState: canvasState))
        self.zoomModel = zoomModel
    }

    var body: some View {
        MetalCanvasView(objects: .constant(scene.renderObjects),
                        interactionMode: .locked2D,
                        clearColor: scene.backgroundColor,
                        pointerHandler: scene.interaction,
                        zoomModel: zoomModel)
            .onAppear {
                scene.setColorScheme(colorScheme)
            }
            .onChange(of: colorScheme) { _, newScheme in
                scene.setColorScheme(newScheme)
            }
    }
}
