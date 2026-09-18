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

    /// Which of the two canvas renderers `MetalCanvasView` should draw. See
    /// `CanvasRenderMode` — this is M4's UI-facing switch; `CanvasSection`
    /// binds a segmented `Picker` to it and forwards the value into
    /// `MetalRenderer.renderMode` on every geometry update.
    @Published var renderMode: CanvasRenderMode = .wireframe

    /// The heightmap surface's current mesh, if there's enough to show one
    /// (a stock and at least one cutting segment). `nil` draws no surface —
    /// same "just don't draw it" handling `MetalRenderer.updateHeightmapMesh`
    /// already gives a mesh with no triangles.
    ///
    /// Rebuilt only by `updateHeightmap`, called from the same places
    /// `updateStock`/`updateToolpath` are (`CanvasSection`'s `onAppear`/
    /// `onChange`), so it's already sitting ready by the time someone flips
    /// `renderMode` to `.heightmap` — switching modes doesn't itself trigger
    /// a carve. `private(set)`: only this file decides when a new carve is
    /// warranted, same as `renderObjects`'s mutations all go through the
    /// `update*` methods below rather than being poked at directly.
    @Published private(set) var heightmapMesh: HeightmapMesh?

    /// Grid resolution for the heightmap carve. Fixed for now — M6's
    /// roadmap item is turning this into a user-facing quality/speed
    /// tradeoff; until then, 0.5mm cells (4x the samples of the original
    /// 1mm default) trade a bit of full-file carve time for far less
    /// visible stair-stepping on the carved surface. Worth revisiting
    /// downward further once M6 lands and a person can choose the
    /// tradeoff themselves rather than eating whatever's hardcoded here.
    private let heightmapCellSize: Float = 0.5

    /// M5: how many `scrubHeightmap` calls to skip between actual recarves.
    /// Dragging the scrub slider (or scrubbing with the scroll wheel) fires
    /// many calls per second; recarving the whole grid on every single one
    /// would make the drag itself feel laggy on anything but a tiny file.
    /// This is the "start simple" throttle the roadmap calls for — M6's
    /// incremental/snapshot carve is the real fix if this interval still
    /// isn't enough on a large program.
    private let heightmapScrubTickInterval = 6

    /// M5: calls to `scrubHeightmap` since the last actual recarve. Reset
    /// whenever a carve happens (`updateHeightmap`) or the surface is
    /// cleared, so a fresh drag always starts counting from zero rather than
    /// picking up wherever the last one left off.
    private var heightmapScrubTickCount = 0

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

    /// Recarves the heightmap grid from scratch and rebuilds `heightmapMesh`
    /// from it — called with the *whole* file's segments for a structural
    /// change (a new stock, a freshly parsed file, a reassigned tool — see
    /// `CanvasSection`), and with just a prefix for a scrub position (see
    /// `scrubHeightmap`, M5's throttled wrapper around this). `segments` is
    /// `some Sequence` rather than `[ToolpathSegment]` so a scrub's
    /// `ArraySlice` (`NCFileDocument.toolpathSegments(upTo:)`) can be handed
    /// straight through — no need to copy it into a fresh `Array` first.
    ///
    /// `tool` is `nil` when the file's `T` number hasn't been assigned a
    /// `ToolSpec` yet (see `GCodeStore.toolSpecAssignments`/`ToolsPickerView`)
    /// — there's no footprint to carve with, so this just clears the surface
    /// rather than guessing a tool size. Only ever carves with one tool for
    /// the whole file; per-segment tool switching for multi-tool programs is
    /// the M6 follow-up `HeightmapGrid.carve(segments:tool:)` already flags.
    func updateHeightmap(stock: StockMaterial, segments: some Sequence<ToolpathSegment>, tool: ToolSpec?) {
        heightmapScrubTickCount = 0

        guard let tool else {
            heightmapMesh = nil
            return
        }

        var grid = HeightmapGrid(stock: stock, cellSize: heightmapCellSize)
        grid.carve(segments: segments, tool: tool)
        heightmapMesh = HeightmapMesh(grid: grid)
    }

    /// M5: the scrub slider's path into `updateHeightmap` — recarves from
    /// the stock up to `line` (via `document.toolpathSegments(upTo:)`)
    /// instead of the whole file, and, unlike `updateHeightmap`, is meant to
    /// be called on *every* scrub tick: it only actually recarves every
    /// `heightmapScrubTickInterval`th call, or whenever `force` is true
    /// (e.g. on slider release, or a structural change that isn't itself a
    /// scrub — see `CanvasSection.forceHeightmapRefresh`). A call that gets
    /// throttled away simply leaves `heightmapMesh` as whatever the last
    /// actual carve produced, same as the wireframe path briefly lags a
    /// fast drag by a few ticks before catching up.
    func scrubHeightmap(stock: StockMaterial, document: NCFileDocument, line: Int, tool: ToolSpec?, force: Bool = false) {
        guard let tool else {
            heightmapMesh = nil
            heightmapScrubTickCount = 0
            return
        }

        heightmapScrubTickCount += 1
        guard force || heightmapScrubTickCount >= heightmapScrubTickInterval else {
            return
        }

        updateHeightmap(stock: stock, segments: document.toolpathSegments(upTo: line), tool: tool)
    }
}
