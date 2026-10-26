//
//  GCodeModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import StratumCAM

@MainActor
class GCodeStore: ObservableObject {

    @Published var document = NCFileDocument() {
        didSet {
            bindDocument()
        }
    }

    @Published var selectedToolpathID: UUID?
    @Published var requestedLine: Int?
    @Published var analyzedLineCount = -1

    /// Spec chosen for each tool number in the current program, keyed by the
    /// tool number itself (the `T` in `T1 M6`). Populated lazily as the
    /// person makes a choice in `ToolsPickerView` — a tool with no entry
    /// here just hasn't been assigned one yet.
    @Published var toolSpecAssignments: [Int: ToolSpec] = [:]

    /// 1-based G-code line the scrub slider is currently parked on. `0` means
    /// nothing has run yet (empty canvas); `document.lines.count` means the
    /// whole program, which is also where this resets to whenever a file
    /// (re)loads — see `ControllerView`'s `toolpathSegments` `onChange`.
    @Published var scrubLine: Int = 0

    // `document` is its own `ObservableObject` (it publishes `lines`, `isLoading`,
    // etc. independently). Views here only ever observe `GCodeStore`, so without
    // this, a change to `document.lines` — e.g. finishing an async file load —
    // never triggers a re-render: `GCodeStore.objectWillChange` only fires when
    // the `document` *reference* itself is reassigned, not when its internal
    // @Published properties mutate. Forwarding its publisher closes that gap.
    private var documentCancellable: AnyCancellable?
    private var headerCancellable: AnyCancellable?

    init() {
        bindDocument()
    }

    private func bindDocument() {
        documentCancellable = document.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Fires once per load (not per line edit) — see
        // `NCFileDocument.loadedHeader`.
        headerCancellable = document.$loadedHeader.sink { [weak self] header in
            self?.applyHeaderTools(header)
        }
    }

    /// Tool specs the loaded file's header declares, by tool number. These
    /// are what `toolSpecAssignments` is seeded with on load, and what
    /// `ToolsPickerView` offers at the top of each tool's list.
    var headerToolSpecs: [Int: ToolSpec] {
        document.loadedHeader?.tools ?? [:]
    }

    /// Makes the header's tools the default assignments for a freshly loaded
    /// file. A file with no header keeps the person's existing library
    /// picks (so regenerating from CAM doesn't wipe them) but drops any
    /// leftover header-derived specs from the previous file, which the picker
    /// would no longer have an option for.
    private func applyHeaderTools(_ header: GCodeHeader?) {
        if let header, !header.tools.isEmpty {
            toolSpecAssignments = header.tools
        } else {
            let kept = toolSpecAssignments.filter { ToolSpec.library.contains($0.value) }
            if kept != toolSpecAssignments {
                toolSpecAssignments = kept
            }
        }
    }

    var allowedContentTypes: [UTType] { Self.allowedContentTypes }

    /// Static so the projects page can offer the same file picker without a store.
    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText]
        for ext in ["nc", "ngc", "gcode", "cnc", "tap"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    /// Distinct tool numbers referenced by the loaded program's `T…`/`M6`
    /// tool changes. Just forwards `document.tools` — that's the cached
    /// value; see `NCFileDocument.recomputeTools`.
    var tools: [Int] {
        // Tools the program calls, in first-appearance order, then any the
        // header declares that no `T… M6` line calls (or that the analyzer
        // couldn't see one for) — so a tool the file describes is always
        // there to inspect and assign.
        let called = document.tools
        let declaredOnly = (document.loadedHeader?.tools.keys.sorted() ?? [])
            .filter { !called.contains($0) }
        return called + declaredOnly
    }

    /// The single `ToolSpec` the heightmap preview carves with (see
    /// `CanvasSceneModel.updateHeightmap`/`scrubHeightmap`) — the first tool
    /// number in the file, in first-appearance order (same order
    /// `ToolsPickerView` lists them), that's actually been assigned a spec.
    /// `nil` if the file has no tools yet, or none of them are assigned —
    /// callers treat that as "nothing to carve with" and clear the surface.
    /// Multi-tool files only ever carve with this one tool for now; see
    /// `HeightmapGrid.carve`'s M6 note on per-segment tool switching.
    /// The `T` number whose section owns `scrubLine` — i.e. whichever tool
    /// is "in the spindle" at the point the canvas is currently scrubbed to
    /// (or, once a running job drives `scrubLine`, at the line actually
    /// executing). `nil` before anything is loaded, past the end of the
    /// file, or during a rapid-only stretch with no tool change yet.
    /// `ToolsPickerView` uses this to highlight the matching row.
    var activeToolNumber: Int? {
        document.toolpath(containingLine: scrubLine)?.toolNumber
    }

    /// The `ToolSpec` to draw on the canvas: the tool actually in the spindle
    /// at `scrubLine` when it's been assigned a spec, otherwise the same
    /// first-assigned tool the heightmap carves with (`activeToolSpec`) —
    /// e.g. past the end of the file, where no section owns the line.
    var spindleToolSpec: ToolSpec? {
        if let number = activeToolNumber, let spec = toolSpecAssignments[number] {
            return spec
        }
        return activeToolSpec
    }

    /// Tool radius in effect on each line of the program, in millimeters,
    /// indexed by 1-based line number (index 0 is unused) — what
    /// `ToolpathBounds.compute` grows each cutting move by.
    ///
    /// A line inside a tool's section gets that tool's assigned radius, or 0
    /// when the tool has no spec yet (a size nobody has told us about isn't
    /// guessed). Lines outside any `T… M6` section — programs that never
    /// change tool — get the first assigned tool's radius, the same fallback
    /// the heightmap carves with (`activeToolSpec`).
    func toolRadiiByLine() -> [Float] {
        let fallback = activeToolSpec.map(ToolFootprint.radius(for:)) ?? 0
        var radii = [Float](repeating: fallback, count: document.lines.count + 1)

        for toolpath in document.toolpaths {
            guard let number = toolpath.toolNumber else {
                continue
            }
            let radius = toolSpecAssignments[number].map(ToolFootprint.radius(for:)) ?? 0
            let first = max(toolpath.startLine, 0)
            let last = min(toolpath.endLine, radii.count - 1)
            guard first <= last else {
                continue
            }
            for line in first...last {
                radii[line] = radius
            }
        }
        return radii
    }

    var activeToolSpec: ToolSpec? {
        for toolNumber in tools {
            if let spec = toolSpecAssignments[toolNumber] {
                return spec
            }
        }
        return nil
    }

    // MARK: - G-code from CAM toolpaths

    /// True while the engine is turning CAM toolpaths into G-code (drives the button's spinner).
    @Published private(set) var isGeneratingFromCAM = false

    /// Something the person needs to know about the last "Use from CAM": either why nothing was
    /// generated, or which toolpaths were left out of a program that was. `ControllerView` shows
    /// it in an alert and clears it.
    @Published var camImportMessage: String?

    /// `CAMModel.revision` the current program was generated from; nil when the
    /// program isn't from CAM. A different current revision means CAM changed since.
    @Published private(set) var generatedFromCAMRevision: Int?

    // MARK: Generation progress

    /// One row of the progress popover: a CAM toolpath and where it is in getting generated.
    struct CAMProgressItem: Identifiable, Equatable {

        enum State: Equatable {
            /// Queued: it has to be generated, but another one is being worked on.
            case waiting
            case generating
            /// Generated and current; it goes into the program.
            case ready
            /// The engine reported an error for it. It stays out of the program.
            case failed(String)
            /// Left out without an error (no shapes, no cutting passes, project changed).
            case skipped(String)

            var isFinished: Bool {
                switch self {
                    case .waiting, .generating: false
                    case .ready, .failed, .skipped: true
                }
            }
        }

        let id: UUID
        let name: String
        var state: State
    }

    /// Every toolpath of the project and its generation state, while "Use from CAM" / "Refresh
    /// from CAM" is generating the ones that weren't ready. Empty otherwise.
    @Published private(set) var camProgress: [CAMProgressItem] = []

    /// Drives the progress popover on the button that started the import.
    @Published var isShowingCAMProgress = false

    /// True once every toolpath is done and the engine is turning them into G-code.
    @Published private(set) var isBuildingCAMGCode = false

    // MARK: Importing

    /// Builds a G-code program from the toolpaths of the CAM project and loads it as the current
    /// document, exactly as if it had been opened from a file (canvas, heightmap, tool list and
    /// the uploader all follow from `document`).
    ///
    /// Toolpaths that were never generated, or were edited since, are generated first — the
    /// same as pressing Generate on each of them in CAM — with the progress shown in a popover.
    /// Toolpaths that still can't make it into the program (no shapes, an engine error…) are
    /// reported in `camImportMessage` afterwards.
    func generateGCode(using camModel: CAMModel) {
        guard !isGeneratingFromCAM else {
            return
        }
        camImportMessage = nil
        isGeneratingFromCAM = true

        Task { [weak self] in
            await self?.importFromCAM(camModel)
        }
    }

    private func importFromCAM(_ camModel: CAMModel) async {

        let pending = camModel.toolpaths.filter { Self.needsGeneration($0, in: camModel) }
        if !pending.isEmpty {
            await generate(pending, in: camModel)
        }

        // Read after the generations above: they are what the program is built from, and they
        // bump `camModel.revision`, which must not make the fresh program look outdated.
        let plan = ToolpathGCodeBuilder.plan(toolpaths: camModel.toolpaths, generations: camModel.generations)
        guard !plan.sections.isEmpty else {
            endCAMImport()
            camImportMessage = plan.nothingToGenerateMessage
            return
        }

        isBuildingCAMGCode = true
        let sections = plan.sections
        let stock = camModel.selectedStockMaterial
        let revision = camModel.revision

        // The engine can take a while on a big job; keep it off the main thread.
        let gcode = await Task.detached(priority: .userInitiated) {
            ToolpathGCodeBuilder.generate(sections, stock: stock)
        }.value

        finishGeneratingFromCAM(gcode: gcode, plan: plan, camRevision: revision)
    }

    /// Generates `pending` one after the other, updating the popover as each one starts and ends.
    /// One at a time keeps the progress readable and the engine from competing with itself.
    private func generate(_ pending: [ToolpathData], in camModel: CAMModel) async {

        let pendingIDs = Set(pending.map(\.id))
        camProgress = camModel.toolpaths.map { toolpath in
            CAMProgressItem(id: toolpath.id,
                            name: toolpath.name,
                            state: pendingIDs.contains(toolpath.id) ? .waiting : Self.state(of: toolpath, in: camModel))
        }
        isShowingCAMProgress = true

        for toolpath in pending {
            setProgress(.generating, for: toolpath.id)
            camModel.generateToolpaths(for: toolpath.id)

            // `generatingIDs` also empties when the run is abandoned (a canvas object changed,
            // the toolpath was deleted), so this can't wait forever.
            while camModel.generatingIDs.contains(toolpath.id) {
                try? await Task.sleep(for: .milliseconds(40))
            }

            // Judge it as it is now: it may have been edited or removed while it ran.
            if let current = camModel.toolpaths.first(where: { $0.id == toolpath.id }) {
                setProgress(Self.state(of: current, in: camModel), for: toolpath.id)
            } else {
                setProgress(.skipped("Removed while generating."), for: toolpath.id)
            }
        }
    }

    private func setProgress(_ state: CAMProgressItem.State, for id: UUID) {
        guard let index = camProgress.firstIndex(where: { $0.id == id }) else {
            return
        }
        camProgress[index].state = state
    }

    /// Whether "Generate" has to run before the toolpath can be posted: it has shapes, and has
    /// either never been generated or was edited since. A toolpath whose current settings
    /// already failed is left alone — running it again would fail the same way.
    private static func needsGeneration(_ toolpath: ToolpathData, in camModel: CAMModel) -> Bool {
        guard !toolpath.targets.isEmpty else {
            return false
        }
        guard let generation = camModel.generations[toolpath.id] else {
            return true
        }
        return !generation.isCurrent(for: toolpath)
    }

    /// Where a toolpath stands right now, judged the same way `ToolpathGCodeBuilder.plan` will.
    private static func state(of toolpath: ToolpathData, in camModel: CAMModel) -> CAMProgressItem.State {
        guard !toolpath.targets.isEmpty else {
            return .skipped("No shapes selected.")
        }
        guard let generation = camModel.generations[toolpath.id] else {
            return .skipped("Discarded, the project changed while generating.")
        }
        if case .failure = generation.outcome {
            return .failed(generation.errorMessage ?? "Generation failed.")
        }
        guard generation.isCurrent(for: toolpath) else {
            return .skipped("Changed while generating.")
        }
        return generation.passCount > 0 ? .ready : .skipped("No cutting passes.")
    }

    /// Closes the popover and clears the import's transient state.
    private func endCAMImport() {
        isGeneratingFromCAM = false
        isBuildingCAMGCode = false
        isShowingCAMProgress = false
        camProgress = []
    }

    private func finishGeneratingFromCAM(gcode: String, plan: ToolpathGCodeBuilder.Plan, camRevision: Int?) {
        endCAMImport()

        guard !gcode.isEmpty else {
            camImportMessage = "The G-code engine didn't produce any output for the generated toolpaths."
            return
        }

        document.load(from: gcode)
        generatedFromCAMRevision = camRevision
        // Same reset the file importer does when a new program replaces the old one.
        selectedToolpathID = nil
        requestedLine = nil
        analyzedLineCount = -1

        if !plan.skipped.isEmpty {
            camImportMessage = plan.partialMessage
        }
    }

    /// Builds a plain-data `RenderObject` for a toolpath (or any point path).
    /// No `MTLDevice` involved — GCodeStore never touches Metal. MetalRenderer
    /// turns this into a GPU buffer once it reaches the canvas.
    func renderObject(forPoints points: [SIMD3<Float>],
                      color: SIMD4<Float>,
                      isDashed: Bool = false,
                      dashLength: Float = 5.0) -> RenderObject? {
        guard !points.isEmpty else {
            return nil
        }
        return RenderObject(points: points,
                            color: color,
                            primitive: .lineStrip,
                            isDashed: isDashed,
                            dashLength: dashLength)
    }

    /// Thin wrapper around `RenderObject.marker(at:...)` kept here so callers
    /// that already hold a `GCodeStore` (e.g. "mark the point under the cursor")
    /// don't need to know that markers are just another `RenderObject`.
//    func markerObject(at point: SIMD3<Float>,
//                      diameter: Float = 6.0,
//                      height: Float = 12.0,
//                      segments: Int = 28,
//                      strutCount: Int = 4,
//                      color: SIMD4<Float> = SIMD4<Float>(1.0, 0.05, 0.05, 1.0)) -> RenderObject {
//        RenderObject.marker(at: point,
//                            diameter: diameter,
//                            height: height,
//                            segments: segments,
//                            strutCount: strutCount,
//                            color: color)
//    }

    func tessellateForRender(_ waypoints: [SC.Waypoint], segmentsPerArc: Int = 32) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        var previous: SC.Waypoint?

        for wp in waypoints {
            switch wp.motion {
                case .rapid, .linear:
                    points.append(SIMD3<Float>(Float(wp.position.x), Float(wp.position.y), Float(wp.position.z)))

                case .arcCW(let center), .arcCCW(let center):
                    guard let prev = previous else {
                        points.append(SIMD3<Float>(Float(wp.position.x), Float(wp.position.y), Float(wp.position.z)))
                        break
                    }

                    let isCCW: Bool
                    if case .arcCCW = wp.motion { isCCW = true } else { isCCW = false }

                    let cx = Double(center.x)
                    let cy = Double(center.y)
                    let radius = hypot(prev.position.x - cx, prev.position.y - cy)
                    let startAngle = atan2(prev.position.y - cy, prev.position.x - cx)
                    var endAngle = atan2(wp.position.y - cy, wp.position.x - cx)

                    // Walk from startAngle to endAngle in the requested direction, wrapping
                    // around as needed so a full sweep is taken rather than the short way.
                    if isCCW {
                        while endAngle <= startAngle { endAngle += 2 * .pi }
                    } else {
                        while endAngle >= startAngle { endAngle -= 2 * .pi }
                    }

                    let steps = max(2, segmentsPerArc)
                    for i in 1...steps {
                        let t = Double(i) / Double(steps)
                        let angle = startAngle + (endAngle - startAngle) * t
                        let x = cx + radius * cos(angle)
                        let y = cy + radius * sin(angle)
                        let z = prev.position.z + (wp.position.z - prev.position.z) * t
                        points.append(SIMD3<Float>(Float(x), Float(y), Float(z)))
                    }
            }
            previous = wp
        }

        return points
    }
}
