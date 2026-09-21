//
//  CAMModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import CoreGraphics
import Combine
import UniformTypeIdentifiers
import AppKit
import StratumCAM

@MainActor
class CAMModel: ObservableObject {

    // ---- PERSISTENT DATA (mirrors ProjectData) ----
    @Published var selectedStockMaterial: StockMaterial {
        didSet {
            canvasState.stock = selectedStockMaterial
            onStockChanged?(selectedStockMaterial)
        }
    }

    // ---- TEMPORARY UI STATE (session-only) ----
    @Published var showingFilePicker = false
    @Published var canvasState = D2_CanvasState()

    // ---- TEMPORARY TOOLPATH EDITING ----
    @Published var toolpaths: [ToolpathData] = []

    /// The toolpath whose settings are open in the right-hand panel; nil closes the panel.
    /// Shape picking follows it: while a toolpath is open the canvas is in picking
    /// mode for it, and closing the panel ends picking (see `syncPickingWithSelection`).
    @Published var selectedToolpathID: UUID? {
        didSet {
            syncPickingWithSelection()
        }
    }

    /// Toolpaths whose generated result is hidden on the canvas (the eye toggle
    /// in the toolpath list). Session-only, like the generated results themselves.
    /// Deliberately no didSet: callers decide whether the overlay needs a rebuild.
    @Published private(set) var hiddenToolpathIDs: Set<UUID> = []

    /// The toolpath currently in "select shapes" mode, if any. While this is
    /// non-nil the canvas is in picking mode (canvasState.isPickingPaths) and
    /// every click on a shape adds/removes it from that toolpath's `targets`.
    @Published private(set) var pickingToolpathID: UUID?

    /// Result of the last "Generate" per toolpath id. Session-only.
    /// Toolpaths whose generation is running in the background right now.
    @Published private(set) var generatingIDs: Set<UUID> = []
    /// Identifies the in-flight run per toolpath. A run only applies its result
    /// if its token is still current — otherwise it was superseded, or the
    /// objects changed underneath it and the result would be stale.
    private var generationTokens: [UUID: UUID] = [:]

    @Published private(set) var generations: [UUID: ToolpathGeneration] = [:] {
        didSet {
            updateToolpathPreview()
        }
    }

    // ---- CANVAS VIEWPORT STATE ----
    // Persisted between sessions. Not @Published: this is *reported* by the
    // canvas (via CAM_2D_View's onViewportChanged) after the user pans/zooms,
    // it never drives a SwiftUI redraw itself — that would fight the canvas's
    // own viewport handling (see CAM_2D_View.updateNSView).
    private(set) var canvasPanOffset: CGPoint = .zero
    private(set) var canvasZoomScale: CGFloat = 3.0
    private(set) var canvasViewportSaved: Bool = false

    var savedViewport: (panOffset: CGPoint, zoomScale: CGFloat)? {
        canvasViewportSaved ? (canvasPanOffset, canvasZoomScale) : nil
    }

    func saveViewport(panOffset: CGPoint, zoomScale: CGFloat) {
        canvasPanOffset = panOffset
        canvasZoomScale = zoomScale
        canvasViewportSaved = true
    }

    let supportedFiles: [UTType] = [.svg, .dxf, .init(filenameExtension: "step")!, .init(filenameExtension: "stp")!, .zip]

    // ---- CALLBACKS FOR PERSISTENCE ----
    var onStockChanged: ((StockMaterial) -> Void)?
    var onToolpathsChanged: (([ToolpathData]) -> Void)?
    /// Fired after any object is added/removed/moved/resized/rotated on the
    /// canvas, with the full current object list. ProjectModel uses this to
    /// mirror each object's transform back into `ProjectData.assets` and
    /// persist it.
    var onObjectsChanged: (([D2_Object]) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    init(selectedStockMaterial: StockMaterial, toolpaths: [ToolpathData]) {
        PerfLog.start()
        self.selectedStockMaterial = selectedStockMaterial
        self.toolpaths = toolpaths
        self.canvasState.stock = selectedStockMaterial

        // D2_CanvasState is an ObservableObject nested inside a @Published
        // property. SwiftUI does NOT forward its objectWillChange up through
        // CAMModel automatically — that's a well-known Combine/SwiftUI gap.
        // Without this line, selecting/editing objects through canvasState
        // would repaint the canvas (which observes canvasState directly) but
        // leave CAMView's body — the inspector, the objects list — stale,
        // since CAMView only observes camModel. This forwards it explicitly.
        canvasState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        canvasState.onObjectsChanged = { [weak self] in
            guard let self else { return }
            // Toolpaths are built in world space, so moving/scaling/rotating/
            // removing an object leaves every generated result stale.
            self.discardGenerations()
            self.onObjectsChanged?(self.canvasState.objects)
        }

        // Picks are written into the toolpath live, so the cell's shape count
        // updates as the user clicks and nothing is lost when the mode closes.
        canvasState.onPickedPathsChanged = { [weak self] paths in
            self?.applyPickedPaths(paths)
        }
    }

    // MARK: Toolpath list

    /// Appends a toolpath — same settings as the last one, or a default first
    /// one — and opens it in the settings panel.
    func addToolpath() {
        var toolpath = toolpaths.last ?? Self.defaultToolpath()
        toolpath.id = UUID()
        toolpath.name = nextToolpathName()
        // Copy the settings, not the shapes: the new toolpath starts with nothing selected
        toolpath.targets = []
        toolpaths.append(toolpath)
        selectedToolpathID = toolpath.id
    }

    /// Clicking a toolpath in the list opens it in the settings panel;
    /// clicking the open one again closes the panel.
    func toggleToolpathSelection(_ id: UUID) {
        selectedToolpathID = (selectedToolpathID == id) ? nil : id
    }

    func deleteToolpath(_ id: UUID) {
        // Closes the panel and ends picking if it was the open one
        if selectedToolpathID == id {
            selectedToolpathID = nil
        }
        // Abandon a generation still running for it
        generationTokens[id] = nil
        generatingIDs.remove(id)
        hiddenToolpathIDs.remove(id)

        toolpaths.removeAll { $0.id == id }
        // Removing the result also refreshes the canvas overlay (see `generations`)
        if generations[id] != nil {
            generations[id] = nil
        }
    }

    /// Shows or hides one toolpath's generated result on the canvas.
    func toggleToolpathVisibility(_ id: UUID) {
        if hiddenToolpathIDs.contains(id) {
            hiddenToolpathIDs.remove(id)
        } else {
            hiddenToolpathIDs.insert(id)
        }
        // Nothing generated means nothing on the canvas to add or remove
        if generations[id]?.previewPath != nil {
            updateToolpathPreview()
        }
    }

    /// "Toolpath N" with the lowest free N past the current count, so names in
    /// the list stay distinguishable (there is no rename UI yet).
    private func nextToolpathName() -> String {
        let existing = Set(toolpaths.map(\.name))
        var number = toolpaths.count + 1
        while existing.contains("Toolpath \(number)") {
            number += 1
        }
        return "Toolpath \(number)"
    }

    private static func defaultToolpath() -> ToolpathData {
        ToolpathData(id: UUID(),
                     name: "Toolpath 1",
                     tool: Tool(id: UUID(),
                                name: "3.175mm",
                                shankDiameter: 3.175,
                                toolDiameter: 3.175,
                                length: 12,
                                type: .endMill,
                                group: nil,
                                tipAngle: nil,
                                parameters: [:]),
                     startZ: 0,
                     endZ: -1,
                     contour: .outline,
                     ramping: RampingSettings(enabled: true,
                                              type: .linear,
                                              angle: 2,
                                              length: 10),
                     feedRate: 0.1,
                     plungeRate: 0.1,
                     spindleRPM: 1200,
                     stepDown: 0.1,
                     stepOver: 0.1,
                     safeZ: 3)
    }

    // MARK: Shape picking

    /// Keeps the canvas's picking mode in step with the open toolpath: opening
    /// one starts picking shapes for it, switching moves picking over to the new
    /// one, closing it stops picking.
    private func syncPickingWithSelection() {
        guard pickingToolpathID != selectedToolpathID else {
            return
        }
        if pickingToolpathID != nil {
            endPicking()
        }
        if let id = selectedToolpathID {
            beginPicking(for: id)
        }
    }

    private func beginPicking(for id: UUID) {
        guard let toolpath = toolpaths.first(where: { $0.id == id }) else {
            return
        }
        // Set before seeding the canvas: seeding can prune stale targets and
        // report that back through applyPickedPaths, which needs this id.
        pickingToolpathID = id
        canvasState.beginPickingPaths(initial: toolpath.targets)
    }

    private func endPicking() {
        pickingToolpathID = nil
        canvasState.endPickingPaths()
    }

    // MARK: Toolpath generation

    /// Runs StratumCAM for the toolpath `id` and stores the outcome (result or
    /// error) in `generations`, where the toolpath's cell reads it from.
    ///
    /// The canvas is read here on the main thread, but the engine run and the
    /// overlay path building happen in the background; the UI stays responsive
    /// and the cell shows a spinner until `finishGeneration` applies the result.
    func generateToolpaths(for id: UUID) {
        guard let toolpath = toolpaths.first(where: { $0.id == id }),
              !generatingIDs.contains(id) else {
            return
        }

        let requestedAt = PerfLog.now()
        PerfLog.log("gen", "▶ Generate requested for '\(toolpath.name)' (\(canvasState.objects.count) object(s) on canvas)")

        let job: ToolpathGenerator.Job
        do {
            job = try ToolpathGenerator.prepare(for: toolpath, canvasState: canvasState)
        } catch {
            // Bad input (no shapes, invalid depth…): report it right away.
            PerfLog.log("gen", "prepare failed: \(ToolpathGenerator.message(for: error))")
            generations[id] = ToolpathGeneration(source: toolpath, outcome: .failure(error), previewPath: nil)
            return
        }
        PerfLog.log("gen", "prepare (main thread) took \(PerfLog.fmt(PerfLog.ms(since: requestedAt)))")

        let token = UUID()
        generationTokens[id] = token
        generatingIDs.insert(id)

        Task { [weak self] in
            let computed = await Task.detached(priority: .userInitiated) { () -> ComputedGeneration in
                do {
                    let outputs = try ToolpathGenerator.run(job)
                    let pathStart = PerfLog.now()
                    let previewPath = ToolpathPathBuilder.path(for: outputs)
                    PerfLog.log("gen", "background work finished; preview path step took \(PerfLog.fmt(PerfLog.ms(since: pathStart)))")
                    return ComputedGeneration(outcome: .success(outputs),
                                              previewPath: previewPath)
                } catch {
                    return ComputedGeneration(outcome: .failure(error), previewPath: nil)
                }
            }.value

            self?.finishGeneration(id: id, token: token, source: toolpath, computed: computed, requestedAt: requestedAt)
        }
    }

    private func finishGeneration(id: UUID, token: UUID, source: ToolpathData, computed: ComputedGeneration, requestedAt: UInt64) {
        guard generationTokens[id] == token else {
            PerfLog.log("gen", "result for '\(source.name)' discarded (superseded, or canvas objects changed while it ran) "
                        + "after \(PerfLog.fmt(PerfLog.ms(since: requestedAt)))")
            return
        }
        generationTokens[id] = nil
        generatingIDs.remove(id)

        PerfLog.log("gen", "applying result on main thread — \(PerfLog.fmt(PerfLog.ms(since: requestedAt))) after the click")
        let applyStart = PerfLog.now()
        // Generating a hidden toolpath means the user wants to see it. No preview
        // rebuild needed here: setting `generations` below does it.
        hiddenToolpathIDs.remove(id)
        generations[id] = ToolpathGeneration(source: source,
                                             outcome: computed.outcome,
                                             previewPath: computed.previewPath)
        PerfLog.log("gen", "◼ applied in \(PerfLog.fmt(PerfLog.ms(since: applyStart))) (state update + preview overlay); "
                    + "total click → applied: \(PerfLog.fmt(PerfLog.ms(since: requestedAt)))")
    }

    /// Drops every result and abandons runs in flight (their tokens no longer match).
    private func discardGenerations() {
        if !generations.isEmpty || !generatingIDs.isEmpty {
            PerfLog.log("gen", "discarding \(generations.count) result(s) and abandoning \(generatingIDs.count) running generation(s) "
                        + "(an object or the project changed)")
        }
        if !generationTokens.isEmpty {
            generationTokens.removeAll()
        }
        if !generatingIDs.isEmpty {
            generatingIDs.removeAll()
        }
        if !generations.isEmpty {
            generations.removeAll()
        }
    }

    /// Redraws the canvas's toolpath overlay from the current results, in the
    /// same order as the toolpath list. Also runs when results are cleared
    /// (object edited, project cleared), which removes the overlay.
    private func updateToolpathPreview() {
        let t0 = PerfLog.now()
        defer {
            PerfLog.log("gen", "updateToolpathPreview took \(PerfLog.fmt(PerfLog.ms(since: t0)))")
        }
        let paths = toolpaths
            .filter { !hiddenToolpathIDs.contains($0.id) }
            .compactMap { generations[$0.id]?.previewPath }

        switch paths.count {
        case 0:
            canvasState.setToolpathsPath(nil)
        case 1:
            canvasState.setToolpathsPath(paths[0])
        default:
            let combined = CGMutablePath()
            paths.forEach { combined.addPath($0) }
            canvasState.setToolpathsPath(combined)
        }
    }

    private func applyPickedPaths(_ paths: [PathSelection]) {
        guard let id = pickingToolpathID,
              let index = toolpaths.firstIndex(where: { $0.id == id }) else {
            return
        }
        toolpaths[index].targets = paths
    }

    @discardableResult
    func loadAndParseFileAt(_ url: URL) -> D2_Object? {

        let ext = url.pathExtension

        switch ext.lowercased() {
            case "svg":
                if let obj = SVGImporter().parse(url: url) {
                    canvasState.add(obj, select: false)
                    return obj
                }

            case "dxf":
                if let obj = DXFImporter().parse(url: url) {
                    canvasState.add(obj, select: false)
                    return obj
                }

            case "step", "stp":
                print("import step")

            case "zip":
                let objs: [D2_Object] = GerberImporter().parse(url: url)
                for obj in objs {
                    canvasState.add(obj, select: false)
                }
                return objs.first

            default:
                print("Unsupported file type: \(ext)")
        }
        return nil
    }

    func clear() {
        endPicking()
        discardGenerations()
        canvasState.removeAll()
        selectedToolpathID = nil
        hiddenToolpathIDs.removeAll()
        toolpaths.removeAll()
    }

    /// True-to-life scale (Points Per MM for current display)
    private(set) var trueToLifeScale: CGFloat = 2.8346

    /// Normalized slider position: 0.0 (min) ... 0.5 (1:1 scale) ... 1.0 (max)
    var sliderPosition: Double {
        get {
            // Map zoomScale -> normalized 0...1 range around trueToLifeScale
            let ratio = canvasState.zoomScale / trueToLifeScale
            let logRatio = log2(ratio) // 0 when 1:1
            let maxLog: Double = 3.3219 // log2(10) -> 10x range

            let normalized = (logRatio / maxLog + 1.0) / 2.0
            return min(max(normalized, 0.0), 1.0)
        }
        set {
            // Map normalized 0...1 slider position -> zoomScale
            let maxLog: Double = 3.3219
            let logRatio = (newValue * 2.0 - 1.0) * maxLog
            let ratio = pow(2.0, logRatio)

            canvasState.zoomScale = trueToLifeScale * ratio
        }
    }

    /// Call this on init or when the NSView moves to a new screen
    func updateTrueToLifeScale(for screen: NSScreen?) {
        guard let screen = screen else { return }

        let deviceDescription = screen.deviceDescription
        guard let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let displaySizeMM = Optional(CGDisplayScreenSize(displayID)), displaySizeMM.width > 0,
              let backingScale = Optional(screen.backingScaleFactor) else {
            return
        }

        // Compute actual physical DPI / point scale
        let pixelWidth = (deviceDescription[NSDeviceDescriptionKey.size] as? NSSize ?? .zero).width * backingScale
        let physicalDPI = (pixelWidth / displaySizeMM.width) * 25.4
        let pointsPerMM = (physicalDPI / 25.4) / backingScale

        self.trueToLifeScale = pointsPerMM
    }

    func resetToTrueToLife() {
        canvasState.zoomScale = trueToLifeScale
    }
}

/// What a background generation hands back to the main actor.
/// `@unchecked Sendable`: the CGPath is fully built before it crosses over and is never mutated afterwards.
private struct ComputedGeneration: @unchecked Sendable {
    let outcome: Result<[SC.OutputToolpath], Error>
    let previewPath: CGPath?
}
