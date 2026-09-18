//
//  CanvasSceneModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import SwiftUI
import simd

/// Everything the 3D canvas needs to draw, kept in its own `ObservableObject`
/// deliberately separate from `ControllerModel`.
///
/// The G-code scrubber mutates `renderObjects` on every slider tick (see
/// `setToolpathVisibleVertexCounts`). `@Published` fires `objectWillChange`
/// for the *whole* object it lives on, not per-property — so if this state
/// lived on `ControllerModel` instead, every view that holds its own
/// `@ObservedObject var model: ControllerModel` (`PanelSpindle`,
/// `PanelMachine`, `PanelCoordinate`, `PanelProbe`, `TerminalView` all do)
/// would re-run its `body` on every scrub tick too, even though none of them
/// touch the canvas. Keeping this scene state here means only the view that
/// actually holds `@ObservedObject var scene: CanvasSceneModel` — the Metal
/// canvas section — re-renders when it changes.
@MainActor
class CanvasSceneModel: ObservableObject {

    /// Plain CPU-side data describing what the 3D canvas should draw. No Metal
    /// types here — MetalRenderer is the only thing that turns this into GPU buffers.
    @Published var renderObjects: [RenderObject] = RenderObject.defaultScene()

    /// Real diameter/length of the tool currently drawn on the canvas, in
    /// millimeters. Defaults to a common 1/8" end mill; set these from the
    /// active `Tool` (`ToolLibrary`/`ToolsStore`) once tool selection is
    /// tracked for a running job, and `updateToolPosition` will pick up the
    /// new size on the next call.
    @Published var toolDiameter: Double = 3.175
    @Published var toolLength: Double = 40

    /// Rebuilds just the stock wireframe from `stock`'s shape and dimensions,
    /// leaving the rest of the scene (axes, toolpath preview, position
    /// marker) untouched. `ControllerView` calls this whenever
    /// `CAMModel.selectedStockMaterial` changes, so the box drawn here always
    /// matches whatever was last set in `MaterialPanelView`.
    func updateStock(_ stock: StockMaterial) {
        renderObjects.updating(.stockBox(for: stock))
    }

    /// Rebuilds the toolpath preview from a freshly (re)parsed G-code file,
    /// replacing whichever rapid/cutting objects were drawn before — axes,
    /// stock, and the position marker are untouched. `ControllerView` calls
    /// this whenever `GCodeStore.document.toolpathSegments` changes, so the
    /// canvas always shows the currently loaded program.
    func updateToolpath(_ segments: [ToolpathSegment]) {
        renderObjects.replacing(roles: [.toolpathRapid, .toolpathCutting],
                                with: RenderObject.toolpath(from: segments))
    }

    /// Narrows how much of the *already-loaded* rapid/cutting toolpath is
    /// drawn — the scrubber's fast path. Unlike `updateToolpath`, this never
    /// re-tessellates: it mutates `visibleVertexCount` in place on the
    /// existing `.toolpathRapid`/`.toolpathCutting` objects, which keeps
    /// their `id`s stable, which is what lets `MetalRenderer.updateGeometry`
    /// reuse their GPU buffers instead of rebuilding them. Cheap enough to
    /// call on every slider tick. Pass the counts from
    /// `NCFileDocument.toolpathVertexCounts(upTo:)`, which is the O(1)
    /// counterpart to the segment slice `updateToolpath` expects.
    func setToolpathVisibleVertexCounts(rapid: Int, cutting: Int) {
        renderObjects.settingVisibleVertexCount(rapid, forRole: .toolpathRapid)
        renderObjects.settingVisibleVertexCount(cutting, forRole: .toolpathCutting)
    }

    /// Rebuilds the cutter wireframe at `point` (the machine's current
    /// work position) using `toolDiameter`/`toolLength`, replacing whatever
    /// was drawn there before — axes, stock, and the toolpath preview are
    /// untouched. Call this whenever the machine reports a new position, or
    /// the scrubber moves the "as-if-running" position.
    func updateToolPosition(_ point: SIMD3<Float>) {
        renderObjects.updating(.tool(at: point, diameter: toolDiameter, length: toolLength))
    }
}
