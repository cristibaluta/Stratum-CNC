//
//  CAMLayersOverlay.swift
//  Stratum CNC
//
//  The legend of the controller's canvas (`CanvasLayersList`), for the CAM
//  screen. It lists only what the CAM canvas has right now: the shapes, the STEP
//  model, the stock, the generated toolpaths, and the anchor and axes that are
//  always there. A project with no STEP model has no Model row, and so on.
//
//  Where the screen already has a switch for something, the checkmark is that
//  switch, so the list and the panels can't disagree:
//    Model  -> `STEPDocumentScene.isModelVisible`
//    Stock  -> the screen's stock visibility (the material panel, saved with the project)
//  The rest (shapes, toolpaths, anchor, axes) are `D2_CanvasState.hiddenLayers`;
//  `CAMSceneModel` leaves them out of the scene.
//

import SwiftUI

struct CAMLayersOverlay: View {

    @ObservedObject var canvasState: D2_CanvasState
    /// Observed so the Model row appears and goes with the STEP model.
    @ObservedObject var workspace: STEPWorkspace
    /// The screen's single funnel for stock visibility (`CAMView.stockVisibleBinding`).
    let isStockVisible: Binding<Bool>
    /// The Toolpaths row (`CAMModel.showsAllToolpaths`): checked, every toolpath is shown while
    /// none is open; the open toolpath is always shown. The row is there while the project has toolpaths.
    var showsAllToolpaths: Binding<Bool> = .constant(false)
    var hasToolpaths = false

    var body: some View {
        if let stepScene = workspace.activeScene {
            // `isModelVisible` is the scene's own, so the row has to watch the scene
            ObservedSTEPScene(scene: stepScene) { scene in
                list(stepScene: scene)
            }
        } else {
            list(stepScene: nil)
        }
    }

    private func list(stepScene: STEPDocumentScene?) -> some View {
        CanvasLayersList(layers: layers(hasModel: stepScene != nil),
                         isVisible: { isVisible($0, stepScene: stepScene) },
                         setVisible: { setVisible($0, $1, stepScene: stepScene) },
                         tint: { tint(for: $0) },
                         label: { label(for: $0) },
                         footer: stepScene.map { AnyView(ProjectionToggle(scene: $0)) })
    }

    /// Only the layers the canvas has content for, in the order they sit in the scene.
    private func layers(hasModel: Bool) -> [CanvasLayer] {
        var layers: [CanvasLayer] = []
        if !canvasState.objects.isEmpty {
            layers.append(.shapes)
        }
        if hasModel {
            layers.append(.model)
        }
        if canvasState.stock != nil {
            layers.append(.stock)
        }
        if hasToolpaths {
            layers.append(.toolpaths)
        }
        layers.append(.anchor)
        layers.append(.axes)
        return layers
    }

    private func isVisible(_ layer: CanvasLayer, stepScene: STEPDocumentScene?) -> Bool {
        switch layer {
            case .model: return stepScene?.isModelVisible ?? false
            case .stock: return canvasState.isStockVisible
            case .toolpaths: return showsAllToolpaths.wrappedValue
            default:     return !canvasState.hiddenLayers.contains(layer)
        }
    }

    private func setVisible(_ layer: CanvasLayer, _ visible: Bool, stepScene: STEPDocumentScene?) {
        switch layer {
            case .model:
                stepScene?.isModelVisible = visible
            case .stock:
                isStockVisible.wrappedValue = visible
            case .toolpaths:
                showsAllToolpaths.wrappedValue = visible
            default:
                if visible {
                    canvasState.hiddenLayers.remove(layer)
                } else {
                    canvasState.hiddenLayers.insert(layer)
                }
        }
    }

    /// CAM calls the anchor its ruler (the controller's canvas keeps "Anchor").
    private func label(for layer: CanvasLayer) -> String {
        switch layer {
            case .anchor:    return "Ruler"
            case .toolpaths: return "All toolpaths"
            default:         return layer.label
        }
    }

    /// The canvas draws the stock in its material's color and the ruler gray, not in the
    /// controller's palette.
    private func tint(for layer: CanvasLayer) -> Color? {
        switch layer {
            case .stock:
                return canvasState.stock.map { Color(canvasColor: $0.material.surfaceColor) }
            case .anchor:
                return Color(canvasColor: CAMSceneModel.Style.rulerColor)
            case .toolpaths:
                return Color(canvasColor: CAMSceneModel.Style.toolpathColor)
            default:
                return layer.tint
        }
    }
}

/// "Z0 projections" checkbox, styled like the layer rows above it. Only there while there is
/// a STEP model; it is the scene's own `showsProjection` (the orange projection of the edges).
private struct ProjectionToggle: View {

    @ObservedObject var scene: STEPDocumentScene

    var body: some View {
        Button {
            scene.showsProjection.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scene.showsProjection ? "checkmark.square.fill" : "square")
                Text("Z0 projections")
                    .font(.caption)
            }
            // The color the projection is drawn in
            .foregroundStyle(Color(canvasColor: CanvasPalette.modelSelection))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Project the model's edges onto z0")
    }
}

/// Re-renders its content when the scene changes (`@ObservedObject` can't hold an optional).
private struct ObservedSTEPScene<Content: View>: View {

    @ObservedObject var scene: STEPDocumentScene
    let content: (STEPDocumentScene) -> Content

    init(scene: STEPDocumentScene, @ViewBuilder content: @escaping (STEPDocumentScene) -> Content) {
        self.scene = scene
        self.content = content
    }

    var body: some View {
        content(scene)
    }
}
