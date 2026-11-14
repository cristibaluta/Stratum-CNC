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
        // `isModelVisible` is each scene's own, so the row has to watch all of them
        ObservedSceneChanges(changes: workspace.sceneChanges) {
            list(stepScenes: workspace.loadedScenes)
        }
    }

    /// The Model row and the projection option stand for every file on the canvas at once.
    private func list(stepScenes: [STEPDocumentScene]) -> some View {
        CanvasLayersList(layers: layers(hasModel: !stepScenes.isEmpty),
                         isVisible: { isVisible($0, stepScenes: stepScenes) },
                         setVisible: { setVisible($0, $1, stepScenes: stepScenes) },
                         tint: { tint(for: $0) },
                         label: { label(for: $0) },
                         footer: stepScenes.isEmpty ? nil : AnyView(ProjectionToggle(scenes: stepScenes)))
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

    private func isVisible(_ layer: CanvasLayer, stepScenes: [STEPDocumentScene]) -> Bool {
        switch layer {
            case .model: return stepScenes.contains { $0.isModelVisible }
            case .stock: return canvasState.isStockVisible
            case .toolpaths: return showsAllToolpaths.wrappedValue
            default:     return !canvasState.hiddenLayers.contains(layer)
        }
    }

    private func setVisible(_ layer: CanvasLayer, _ visible: Bool, stepScenes: [STEPDocumentScene]) {
        switch layer {
            case .model:
                stepScenes.forEach { $0.isModelVisible = visible }
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
/// a STEP model; it sets the scenes' own `showsProjection` (the orange projection of the edges),
/// in every file on the canvas.
private struct ProjectionToggle: View {

    let scenes: [STEPDocumentScene]

    private var isOn: Bool { scenes.allSatisfy(\.showsProjection) }

    var body: some View {
        Button {
            let on = !isOn
            scenes.forEach { $0.showsProjection = on }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
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

/// Re-renders its content whenever any scene of the workspace changes.
private struct ObservedSceneChanges<Content: View>: View {

    @ObservedObject var changes: STEPSceneChanges
    let content: () -> Content

    init(changes: STEPSceneChanges, @ViewBuilder content: @escaping () -> Content) {
        self.changes = changes
        self.content = content
    }

    var body: some View {
        content()
    }
}
