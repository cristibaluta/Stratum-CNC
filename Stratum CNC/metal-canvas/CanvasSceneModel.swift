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

    /// Grid resolution for the heightmap carve, in millimeters — M6's
    /// user-facing quality/speed tradeoff. Smaller cells mean more samples
    /// (finer, slower carve, less visible stair-stepping); larger cells
    /// mean fewer samples (coarser, faster carve). Exposed via
    /// `HeightmapQualityPickerView` in the canvas overlay, ranging from
    /// 0.1mm (best quality) to 0.5mm (fastest).
    ///
    /// Changing this alone doesn't recarve — same as `renderMode`, it just
    /// needs to be in place before the *next* carve. `CanvasSection` forces
    /// one on change, same as it does for a reassigned tool.
    @Published var heightmapCellSize: Float = 0.1

    /// XY offset applied to the stock/toolpath/heightmap, in millimeters —
    /// lets the user nudge the job's origin on the canvas without touching
    /// the underlying G-code. Same "just state" pattern as
    /// `heightmapCellSize`: setting this alone doesn't move anything on
    /// screen. The GPU line draws (`.toolpathRapid`/`.toolpathCutting`) and
    /// the tool marker (`.tool`) pick it up every frame via `MetalRenderer`'s
    /// offset uniform; the heightmap
    /// surface needs an actual recarve to reflect a new value, same as
    /// `heightmapCellSize` does, and `CanvasSection` triggers that the same
    /// way (`onChange` + `forceHeightmapRefresh()`).
    @Published var xyOffset: SIMD2<Float> = .zero

    /// Base color the heightmap surface is shaded with — the selected
    /// stock's material color (`StockMaterialType.surfaceColor`), so the 3D
    /// preview matches whatever was picked in `MaterialPanelView`. Set by
    /// `updateStock`. The default is the old fixed "machined aluminum" gray,
    /// only visible until the first `updateStock` runs.
    @Published var stockColor: SIMD4<Float> = SIMD4<Float>(0.75, 0.72, 0.68, 1.0)

    /// M5: how many `scrubHeightmap` calls to skip between actual recarves.
    /// Dragging the scrub slider (or scrubbing with the scroll wheel) fires
    /// many calls per second; even with M6 step 1's incremental carve
    /// (`HeightmapCarveCache`) making each individual recarve cheap, there's
    /// still no reason to run one on every tick of a fast drag when the
    /// result would just be replaced a few milliseconds later.
    private let heightmapScrubTickInterval = 6

    /// M5: calls to `scrubHeightmap` since the last actual recarve. Reset
    /// whenever a carve happens (`updateHeightmap`) or the surface is
    /// cleared, so a fresh drag always starts counting from zero rather than
    /// picking up wherever the last one left off.
    private var heightmapScrubTickCount = 0

    /// `true` from the moment a heightmap carve is handed to a background
    /// task until its mesh — or the last of a coalesced run of them — has
    /// landed in `heightmapMesh`. `CanvasSection` shows a spinner over the
    /// canvas while this is set. Only ever assigned through
    /// `setComputingHeightmap`, which skips no-op writes: a `@Published`
    /// fires on every assignment, and this object's own doc comment explains
    /// what redundant publishes cost.
    @Published private(set) var isComputingHeightmap = false

    /// The in-flight background carve, if any. Non-`nil` exactly while
    /// `isComputingHeightmap` is `true`.
    private var heightmapTask: Task<Void, Never>?

    /// Bumped whenever a carve starts or is cancelled. A finished carve only
    /// publishes its mesh if the number it started with is still current, so
    /// a superseded task can never overwrite a newer result — cancellation
    /// alone can't guarantee that, since a task can finish just before it is
    /// cancelled and still be waiting for its turn on the main actor.
    private var heightmapGeneration = 0

    /// A throttled scrub tick that arrived while a carve was already
    /// running. Only the newest one is kept; it starts as soon as the
    /// running carve lands, so a long drag shows a stream of intermediate
    /// surfaces instead of nothing until release.
    private var pendingHeightmapRequest: HeightmapRequest?

    /// M6, step 1: the incremental-carve cache. Holds the grid as last
    /// carved plus its periodic snapshots, so the *next* `updateHeightmap`/
    /// `scrubHeightmap` call — forward or backward — only carves the
    /// segments between that position and the new one, instead of redoing
    /// the whole prefix (see `HeightmapCarveCache`). Captured into a
    /// `HeightmapRequest` at request time same as `stock`/`tool`/etc, and
    /// overwritten with whatever `finishHeightmapCarve` gets back — even
    /// from a cancelled carve, whose partial forward progress is still
    /// worth keeping (see that method).
    ///
    /// `nil` before the first carve, and cleared whenever there's no tool
    /// to carve with (`updateHeightmap`/`scrubHeightmap`'s `tool == nil`
    /// branches) — a cache holds onto its grid and every snapshot it's
    /// taken, so there's no reason to keep that memory around once there's
    /// nothing it can be reused for.
    private var heightmapCarveCache: HeightmapCarveCache?

    /// Segments between snapshots the cache takes while carving forward —
    /// see `HeightmapCarveCache.snapshotInterval`. 256 is a starting point,
    /// not a measured optimum: small enough that even a big backward scrub
    /// rarely replays more than a couple hundred segments, large enough
    /// that a full-length file doesn't blow past `HeightmapCarveCache`'s
    /// snapshot cap (and so start thinning, coarsening the fallback) too
    /// quickly.
    private let heightmapSnapshotInterval = 256

    /// Rebuilds just the stock wireframe from `stock`'s shape and dimensions,
    /// leaving the rest of the scene (axes, toolpath preview, position
    /// marker) untouched. `ControllerView` calls this whenever
    /// `CAMModel.selectedStockMaterial` changes, so the box drawn here always
    /// matches whatever was last set in `MaterialPanelView`.
    ///
    /// The static workbed and anchor are rebuilt here too: they're flat, and
    /// sit at the stock's bottom face, so a change in stock depth moves them.
    func updateStock(_ stock: StockMaterial) {
        stockColor = stock.material.surfaceColor
        renderObjects.updating(.stockBox(for: stock))
        for fixture in RenderObject.fixtures(for: stock) {
            renderObjects.updating(fixture)
        }
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
    /// an `ArraySlice` so a scrub's prefix
    /// (`NCFileDocument.toolpathSegments(upTo:)`) can be handed straight
    /// through with no copy — and, being a value that shares the document's
    /// buffer copy-on-write, it's safe to hand to a background task.
    ///
    /// The carve and the mesh build run off the main thread (see
    /// `startHeightmapCarve`), so this returns immediately; `heightmapMesh`
    /// updates when the work lands, and `isComputingHeightmap` is `true` in
    /// between. Until then the previous surface stays on screen.
    ///
    /// `supersedesRunning` decides what happens if a carve is already in
    /// flight. `true` (the default — structural changes and exact refreshes)
    /// cancels it and starts over, since its result would be for stale
    /// inputs. `false` (throttled scrub ticks) lets it finish and keeps this
    /// request as the one to run next, replacing any older waiting one.
    ///
    /// `tool` is `nil` when the file's `T` number hasn't been assigned a
    /// `ToolSpec` yet (see `GCodeStore.toolSpecAssignments`/`ToolsPickerView`)
    /// — there's no footprint to carve with, so this just clears the surface
    /// rather than guessing a tool size. Only ever carves with one tool for
    /// the whole file; per-segment tool switching for multi-tool programs is
    /// the M6 follow-up `HeightmapGrid.carve(segments:tool:)` already flags.
    ///
    /// Always carves with the current `xyOffset` — same value the GPU line
    /// draws are shifted by (see `MetalRenderer.xyOffset`), so the shaded
    /// heightmap surface and the wireframe toolpath preview never disagree
    /// about where the job sits, even though they get there by different
    /// means (this bakes the offset into the carved vertices once per carve;
    /// the GPU path re-applies its uniform every frame). The stock, tool,
    /// cell size and offset are all read *here*, at request time, so a carve
    /// always finishes with the inputs it was asked for even if they change
    /// again while it runs.
    func updateHeightmap(stock: StockMaterial,
                         segments: ArraySlice<ToolpathSegment>,
                         tool: ToolSpec?,
                         supersedesRunning: Bool = true) {
        // Nothing draws the surface outside `.heightmap` mode (see
        // `MetalRenderer.draw`), so carving and meshing here would be pure
        // wasted work. `CanvasSection` forces a recarve when the mode is
        // switched *to* `.heightmap`, so the surface is current the moment
        // it's needed. Leaving the mode also abandons any carve still
        // running, so it doesn't keep burning a core for a surface nobody
        // can see.
        guard renderMode == .heightmap else {
            stopHeightmapWork()
            return
        }

        heightmapScrubTickCount = 0

        guard let tool else {
            stopHeightmapWork()
            heightmapMesh = nil
            heightmapCarveCache = nil
            return
        }

        let request = HeightmapRequest(stock: UncheckedSendable(stock),
                                       segments: segments,
                                       tool: tool,
                                       cellSize: heightmapCellSize,
                                       offset: xyOffset,
                                       cache: UncheckedSendable(heightmapCarveCache),
                                       snapshotInterval: heightmapSnapshotInterval)

        if supersedesRunning {
            cancelHeightmapWork()
            startHeightmapCarve(request)
        } else if heightmapTask != nil {
            pendingHeightmapRequest = request
        } else {
            startHeightmapCarve(request)
        }
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
    ///
    /// A forced call cancels any carve still running; an unforced one waits
    /// its turn behind it (see `updateHeightmap`'s `supersedesRunning`).
    func scrubHeightmap(stock: StockMaterial, document: NCFileDocument, line: Int, tool: ToolSpec?, force: Bool = false) {
        // See `updateHeightmap`: no surface is drawn in wireframe mode, so a
        // scrub there shouldn't touch the heightmap at all.
        guard renderMode == .heightmap else {
            stopHeightmapWork()
            return
        }

        guard let tool else {
            stopHeightmapWork()
            heightmapMesh = nil
            heightmapCarveCache = nil
            heightmapScrubTickCount = 0
            return
        }

        heightmapScrubTickCount += 1
        guard force || heightmapScrubTickCount >= heightmapScrubTickInterval else {
            return
        }

        updateHeightmap(stock: stock,
                        segments: document.toolpathSegments(upTo: line),
                        tool: tool,
                        supersedesRunning: force)
    }

    // MARK: Background carve

    /// Hands `request` to a background task. Only the final publish hops
    /// back to the main actor — same shape as `NCFileDocument.load(from:)`,
    /// including `Task.detached` rather than `Task { }`: this method is
    /// `@MainActor`-isolated, and a plain `Task { }` would inherit that and
    /// run the carve on the main thread again.
    private func startHeightmapCarve(_ request: HeightmapRequest) {
        heightmapGeneration += 1
        let generation = heightmapGeneration
        setComputingHeightmap(true)

        heightmapTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.carveMesh(for: request)
            guard let self else {
                return
            }
            await self.finishHeightmapCarve(result.mesh, cache: result.cache, generation: generation)
        }
    }

    /// Runs on the main actor. Drops the result if a newer carve (or a
    /// cancel) has happened since `generation` was issued; otherwise
    /// publishes it and either starts the waiting request or turns the
    /// spinner off. `mesh` is `nil` only for a carve that noticed its own
    /// cancellation — which always means the generation is stale too, so it
    /// never reaches the publish below.
    ///
    /// `cache` is committed even when `mesh` is `nil`: a cancelled carve
    /// may still have carved forward some way before it noticed (see
    /// `HeightmapCarveCache.carveForward`'s check every 1024 segments), and
    /// that progress is exactly as reusable as if it had come from a carve
    /// that ran to completion — dropping it would just mean redoing it on
    /// the next request for no reason.
    private func finishHeightmapCarve(_ mesh: HeightmapMesh?, cache: HeightmapCarveCache, generation: Int) {
        guard generation == heightmapGeneration else {
            return
        }
        heightmapTask = nil
        heightmapCarveCache = cache

        if let mesh {
            heightmapMesh = mesh
        }

        if let next = pendingHeightmapRequest {
            pendingHeightmapRequest = nil
            startHeightmapCarve(next)
        } else {
            setComputingHeightmap(false)
        }
    }

    /// Cancels the running carve and forgets any waiting request. Leaves
    /// `isComputingHeightmap` alone: callers that go on to start another
    /// carve shouldn't blink the spinner off and on.
    private func cancelHeightmapWork() {
        heightmapGeneration += 1
        heightmapTask?.cancel()
        heightmapTask = nil
        pendingHeightmapRequest = nil
    }

    /// Cancels everything and clears the spinner. A no-op (and no publish)
    /// when nothing is running, which is the common case for a scrub tick
    /// in wireframe mode.
    private func stopHeightmapWork() {
        guard isComputingHeightmap else {
            return
        }
        cancelHeightmapWork()
        setComputingHeightmap(false)
    }

    private func setComputingHeightmap(_ value: Bool) {
        if isComputingHeightmap != value {
            isComputingHeightmap = value
        }
    }

    /// The actual work: bring the carve cache up to `request.segments`
    /// (incrementally — see `HeightmapCarveCache` — rather than always
    /// from scratch) and mesh the result. `nonisolated` so it genuinely
    /// runs on the calling background task rather than hopping back to the
    /// main actor.
    ///
    /// `mesh` is `nil` if the task was cancelled part-way through carving
    /// (checked every 1024 segments — see `HeightmapCarveCache
    /// .carveForward`) or just before the mesh build, which is one
    /// uninterruptible pass; `cache` is returned either way; see
    /// `finishHeightmapCarve` for why that's still useful on cancellation.
    private nonisolated static func carveMesh(for request: HeightmapRequest) -> (mesh: HeightmapMesh?, cache: HeightmapCarveCache) {
        let emptyGrid = HeightmapGrid(stock: request.stock.value, cellSize: request.cellSize)
        let setup = HeightmapCarveCache.Setup(grid: emptyGrid, tool: request.tool, offset: request.offset)

        // Reuse the cached grid only if it was carved with the same shape,
        // mask, tool, and offset — anything else and there's no valid
        // partial state to build on, so start clean instead (still exactly
        // as cheap as a full recarve always was).
        var cache: HeightmapCarveCache
        if let existing = request.cache.value, existing.setup == setup {
            cache = existing
        } else {
            cache = HeightmapCarveCache(setup: setup, grid: emptyGrid, snapshotInterval: request.snapshotInterval)
        }

        guard let grid = cache.carve(through: request.segments) else {
            return (nil, cache)
        }
        guard !Task.isCancelled else {
            return (nil, cache)
        }
        return (HeightmapMesh(grid: grid), cache)
    }
}

// MARK: - Background carve support

/// Everything a background carve needs, captured on the main actor at
/// request time so the task never reads live model state.
private struct HeightmapRequest: Sendable {
    let stock: UncheckedSendable<StockMaterial>
    let segments: ArraySlice<ToolpathSegment>
    let tool: ToolSpec
    let cellSize: Float
    let offset: SIMD2<Float>
    /// The incremental-carve cache as last committed by
    /// `finishHeightmapCarve`, if any — `nil` before the first carve.
    /// `HeightmapCarveCache` is a plain value type (arrays of `Float`/
    /// `Bool`, a `HeightmapGrid`, a `ToolSpec`), so wrapping it here follows
    /// the same `UncheckedSendable` pattern `stock` already does rather
    /// than chasing `Sendable` conformance through every type it's made of.
    let cache: UncheckedSendable<HeightmapCarveCache?>
    /// Threaded through from `CanvasSceneModel.heightmapSnapshotInterval`
    /// so `HeightmapCarveCache`'s own default doesn't drift from the one
    /// actually in effect — only used the first time a cache is created for
    /// a given `Setup`; an existing cache keeps whatever interval it's
    /// already thinned its way to (see `HeightmapCarveCache
    /// .thinSnapshotsIfNeeded`).
    let snapshotInterval: Int
}

/// `StockMaterial` is defined in the CAM module and isn't declared
/// `Sendable` where this file can see it. It's a plain value type (a shape
/// plus a material), so moving a copy to another thread is safe in practice;
/// this wrapper says so to the compiler in one place instead of loosening
/// the whole request. If `StockMaterial` is (or becomes) `Sendable`, this
/// can go.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
