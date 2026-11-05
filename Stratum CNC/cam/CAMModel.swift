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
    /// Bumped whenever something the generated G-code is built from changes: the
    /// toolpath settings, their generated results, or the stock. The Controller
    /// compares it with the value its program was generated at to know when that
    /// program is out of date (see `GCodeStore.generatedFromCAMRevision`).
    @Published private(set) var revision = 0

    @Published var selectedStockMaterial: StockMaterial {
        didSet {
            revision &+= 1
            canvasState.stock = selectedStockMaterial
            // A turned setup is built from the stock's size, so its results are outdated too
            if setups.contains(where: { $0.angle != 0 }) {
                discardGenerations()
            }
            onStockChanged?(selectedStockMaterial)
        }
    }

    /// How the stock is held, in the order the setups are machined (see `Setup`). Never empty:
    /// a project always has at least the top. `toolpaths` is kept in the same order: all of the
    /// first setup's toolpaths, then the second's… (see `orderedBySetup`), so the G-code of one
    /// setup is a contiguous run of the list.
    @Published private(set) var setups: [Setup] {
        didSet {
            revision &+= 1
            onSetupsChanged?(setups)
            // Renaming or reordering changes nothing that is cut; a different orientation does
            if Self.orientations(of: oldValue) != Self.orientations(of: setups) {
                discardGenerations()
            }
        }
    }

    /// The setup the toolpath list is looking at: "Add toolpath" adds to it, and its toolpaths are
    /// the ones drawn on the canvas. Opening a toolpath makes its setup the active one.
    @Published private(set) var activeSetupID: UUID {
        didSet {
            if oldValue != activeSetupID {
                updateToolpathPreview()
            }
        }
    }

    // ---- TEMPORARY UI STATE (session-only) ----
    @Published var showingFilePicker = false
    @Published var canvasState = D2_CanvasState()
    let stepWorkspace = STEPWorkspace()

    /// Bridges the canvas's 100% button to `CAM_Metal_View`'s
    /// `MetalCanvasView` — see `CanvasZoomModel`. Unrelated to the legacy
    /// `canvasZoomScale`/`trueToLifeScale` below, which belonged to the old
    /// CoreAnimation 2D canvas's own `CanvasZoomToolbar`.
    let canvasZoomModel = CanvasZoomModel()

    // ---- TEMPORARY TOOLPATH EDITING ----
    @Published var toolpaths: [ToolpathData] = [] {
        didSet {
            revision &+= 1
            onToolpathsChanged?(toolpaths)
            // Switching a rest toolpath to another operation starts (or ends) shape picking
            syncPickingWithSelection()
            // Editing or deleting a pocket outdates the rest toolpaths linked to it
            refreshLinkedGenerations()
            updateRestRegions()
            // An edit can make the open toolpath's result outdated, which ends scrubbing
            syncScrub()
            syncHoldingTabs()
        }
    }

    /// The toolpath whose settings are open in the right-hand panel; nil closes the panel.
    /// Shape picking follows it: while a toolpath is open the canvas is in picking
    /// mode for it, and closing the panel ends picking (see `syncPickingWithSelection`).
    @Published var selectedToolpathID: UUID? {
        didSet {
            // The open toolpath's setup becomes the active one
            if let id = selectedToolpathID,
               let setupID = toolpaths.first(where: { $0.id == id })?.setupID,
               setups.contains(where: { $0.id == setupID }) {
                activeSetupID = setupID
            }
            // A toolpath and objects are never selected together
            if selectedToolpathID != nil, !canvasState.selectedObjectIDs.isEmpty {
                canvasState.clearSelection()
            }
            syncPickingWithSelection()
            syncScrub()
            syncHoldingTabs()
            updateRestRegions()
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
            revision &+= 1
            // The preview below depends on whether something is being scrubbed, so sort that out first
            syncScrub(refreshPreview: false)
            updateToolpathPreview()
        }
    }

    /// How generated toolpaths are drawn and previewed on this canvas: which passes
    /// of each one. CAM's top-down canvas keeps one; a 3D scene would set
    /// `.canvas3D` to keep them all. Read when a generation starts, so a change
    /// applies from the next Generate, not to results already on screen.
    var previewOptions: ToolpathPreviewOptions = .canvas2D

    /// Draw the corners the open pocket's tool couldn't reach (see `updateRestRegions`).
    @Published var showsRestAreas = true {
        didSet {
            updateRestRegions()
        }
    }

    /// Which generation the canvas is scrubbing right now (see `syncScrub`).
    private var scrubbedGenerationID: UUID?

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
    /// Fired when a setup is added, removed, renamed, reordered or turned. ProjectModel saves them
    /// with the project (the toolpaths refer to them by id).
    var onSetupsChanged: (([Setup]) -> Void)?
    /// Fired after any object is added/removed/moved/resized/rotated on the
    /// canvas, with the full current object list. ProjectModel uses this to
    /// mirror each object's transform back into `ProjectData.assets` and
    /// persist it.
    var onObjectsChanged: (([D2_Object]) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    /// - Parameter setups: the project's saved setups. Empty for a project saved before setups
    ///   existed: it gets the top, and every toolpath goes in it.
    init(selectedStockMaterial: StockMaterial, toolpaths: [ToolpathData], setups: [Setup] = []) {
        PerfLog.start()
        let initialSetups = setups.isEmpty ? [Setup(face: .top)] : setups
        self.setups = initialSetups
        self.activeSetupID = initialSetups[0].id
        self.selectedStockMaterial = selectedStockMaterial
        self.toolpaths = Self.orderedBySetup(toolpaths, setups: initialSetups)
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
        stepWorkspace.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // Toolpaths cut from a STEP model's edges follow its position, like an object's
        stepWorkspace.onModelMoved = { [weak self] in self?.discardGenerations() }

        canvasState.onObjectsChanged = { [weak self] in
            guard let self else { return }
            // Toolpaths are built in world space, so moving/scaling/rotating/
            // removing an object leaves every generated result stale.
            self.discardGenerations()
            self.onObjectsChanged?(self.canvasState.objects)
        }

        // Selecting an object closes the open toolpath
        canvasState.onObjectSelected = { [weak self] in
            guard let self, self.selectedToolpathID != nil else { return }
            self.selectedToolpathID = nil
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
    /// - Parameter targets: the shapes the new toolpath starts with. Settings are
    ///   copied from the last toolpath, never its shapes, so the default is none.
    /// - Parameter stepTargets: the STEP edges it starts with; its End Z is then the depth of those edges.
    /// - Parameter setupID: the setup it is cut in; the active one by default. Settings are copied from
    ///   the last toolpath of that setup, or from the last one of any setup when it has none yet.
    func addToolpath(targets: [PathSelection] = [], stepTargets: [STEPEdgeTarget] = [], setupID: UUID? = nil) {
        let setupID = setupID.flatMap { id in setups.contains { $0.id == id } ? id : nil } ?? activeSetupID
        var toolpath = toolpaths.last(where: { $0.setupID == setupID }) ?? toolpaths.last ?? Self.defaultToolpath()
        toolpath.id = UUID()
        toolpath.setupID = setupID
        // A rest toolpath is tied to its pocket, so a copy of it would be one too: start from
        // the pocket's kind of operation instead.
        if toolpath.operation.kind == .restMachining {
            toolpath.operation.kind = .pocket
            toolpath.operation.restSourceID = nil
        }
        // A fresh copy gets its own auto name for its operation.
        toolpath.name = toolpath.operation.kind.nextName(among: Set(toolpaths.map(\.name)))
        toolpath.targets = targets
        toolpath.stepTargets = stepTargets
        // Cut as deep as the selected edges are below z0. Marked as set, so changing the
        // operation later doesn't put its default depth back.
        if let endZ = stepWorkspace.suggestedEndZ(for: stepTargets, frame: frameOrIdentity(for: toolpath)) {
            toolpath.endZ = endZ
            toolpath.editedFields.insert(.endZ)
        }
        // At the end of its setup's run, not of the whole list
        toolpaths = Self.orderedBySetup(toolpaths + [toolpath], setups: setups)
        // Opening it starts picking, seeded with `targets` (see `beginPicking`),
        // which also clears the plain canvas selection they came from.
        selectedToolpathID = toolpath.id
    }

    /// "Create rest operation" on a previewed pocket: a new toolpath right after it that cuts the
    /// corners the pocket's tool couldn't reach, with a smaller tool. Everything else (feeds,
    /// Z levels, entry, direction) is copied from the pocket. Linked, not copied: the corners are
    /// recomputed from the pocket on every Preview (see `OperationSettings.restSourceID`).
    func addRestToolpath(from sourceID: UUID) {
        guard let index = toolpaths.firstIndex(where: { $0.id == sourceID }),
              toolpaths[index].operation.kind == .pocket else {
            return
        }
        let source = toolpaths[index]

        var rest = source
        rest.id = UUID()
        rest.targets = []
        rest.operation.kind = .restMachining
        rest.operation.restSourceID = sourceID
        rest.operation.pocketPattern = .offset
        rest.operation.stockToLeave = 0
        rest.operation.finishingPass = false
        // One plunge to the pocket's End Z: stepdown equals the depth (both editable afterwards).
        rest.endZ = source.endZ
        rest.stepDown = max(abs(source.endZ), 0.01)
        rest.name = OperationKind.restMachining.nextName(among: Set(toolpaths.map(\.name)))

        // A tool half the pocket's size, to start from; the user picks the real one in the panel.
        // It needs an id of its own: the G-code header numbers tools by id.
        let diameter = max(0.1, (source.tool.toolDiameter / 2 * 10).rounded() / 10)
        rest.tool = Tool(name: String(format: "%gmm", diameter),
                         shankDiameter: min(source.tool.shankDiameter, max(diameter, 3)),
                         toolDiameter: diameter,
                         cuttingHeight: source.tool.cuttingHeight,
                         type: source.tool.type,
                         tipAngle: source.tool.tipAngle)

        toolpaths.insert(rest, at: index + 1)
        selectedToolpathID = rest.id
    }

    /// The shapes selected with the mouse that a new toolpath could be built from.
    /// Empty while a toolpath is open: the canvas is in picking mode then, and
    /// clicks edit that toolpath's shapes instead of the plain selection.
    var shapesForNewToolpath: [PathSelection] {
        selectedToolpathID == nil ? canvasState.selectedPaths : []
    }

    /// The STEP edges selected in the 3D canvas that a new toolpath could be built from.
    /// Empty while a toolpath is open (clicks edit that toolpath's edges then).
    var stepEdgesForNewToolpath: [STEPEdgeTarget] {
        guard selectedToolpathID == nil,
              let scene = stepWorkspace.activeScene else { return [] }
        return scene.selectedEdges.sorted { ($0.bodyID.entityID, $0.entityID) < ($1.bodyID.entityID, $1.entityID) }
            .map(STEPEdgeTarget.init)
    }

    /// "Add toolpath" from the canvas tooltip: a new toolpath that cuts the selected shapes
    /// (or, in the 3D canvas, the selected STEP edges).
    func addToolpathFromSelection() {
        let edges = stepEdgesForNewToolpath
        if !edges.isEmpty {
            addToolpath(stepTargets: edges)
            return
        }
        let targets = shapesForNewToolpath
        guard !targets.isEmpty else {
            return
        }
        addToolpath(targets: targets)
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

    /// Moves a toolpath to `newIndex` in the list (its index once it has moved). The list
    /// order is the order the toolpaths are written to the G-code program, so this is how the
    /// user decides which one is cut first. Results stay attached to their toolpath: they are
    /// keyed by id, so nothing needs to be generated again.
    func moveToolpath(_ id: UUID, to newIndex: Int) {
        guard let from = toolpaths.firstIndex(where: { $0.id == id }) else {
            return
        }
        let to = min(max(newIndex, 0), toolpaths.count - 1)
        guard from != to else {
            return
        }
        var reordered = toolpaths
        reordered.insert(reordered.remove(at: from), at: to)
        // Saves the project through `onToolpathsChanged`
        toolpaths = reordered
        // The preview is drawn in list order
        updateToolpathPreview()
    }

    /// Moves a toolpath to `newIndex` among the toolpaths of its own setup. The panel's drag works
    /// inside one setup's section, so this is its index there, not in the whole list.
    func moveToolpath(_ id: UUID, toIndexInSetup newIndex: Int) {
        guard let setupID = toolpaths.first(where: { $0.id == id })?.setupID else {
            return
        }
        let group = toolpaths.filter { $0.setupID == setupID }
        guard let from = group.firstIndex(where: { $0.id == id }) else {
            return
        }
        let to = min(max(newIndex, 0), group.count - 1)
        guard from != to else {
            return
        }
        var reordered = group
        reordered.insert(reordered.remove(at: from), at: to)
        // The setup's toolpaths go back into the slots they occupied
        var next = reordered.makeIterator()
        var result = toolpaths
        for index in result.indices where result[index].setupID == setupID {
            if let toolpath = next.next() {
                result[index] = toolpath
            }
        }
        toolpaths = result
        updateToolpathPreview()
    }

    /// Moves a toolpath to the end of another setup. Its results are outdated by the move (the
    /// setup is part of what they were generated from), and a pocket takes its rest toolpaths
    /// along. A rest toolpath can't move alone: it has to stay with its pocket.
    func moveToolpath(_ id: UUID, toSetup setupID: UUID) {
        guard setups.contains(where: { $0.id == setupID }),
              let toolpath = toolpaths.first(where: { $0.id == id }),
              toolpath.setupID != setupID,
              toolpath.operation.kind != .restMachining else {
            return
        }
        let moving = Set([id] + toolpaths.filter {
            $0.operation.kind == .restMachining && $0.operation.restSourceID == id
        }.map(\.id))
        var moved = toolpaths.filter { moving.contains($0.id) }
        for index in moved.indices {
            moved[index].setupID = setupID
        }
        let staying = toolpaths.filter { !moving.contains($0.id) }
        toolpaths = Self.orderedBySetup(staying + moved, setups: setups)
        updateToolpathPreview()
    }

    // MARK: Setups

    func setup(withID id: UUID?) -> Setup? {
        id.flatMap { id in setups.first { $0.id == id } }
    }

    /// The toolpath's setup. A toolpath whose setup is gone (it was saved without setups) is in the first.
    func setup(for toolpath: ToolpathData) -> Setup {
        setup(withID: toolpath.setupID) ?? setups[0]
    }

    func toolpaths(in setupID: UUID) -> [ToolpathData] {
        toolpaths.filter { $0.setupID == setupID }
    }

    /// The map into the toolpath's setup. Throws a message for the Generate button when this
    /// stock or angle can't be handled (see `SetupFrame.make`).
    func setupFrame(for toolpath: ToolpathData) throws -> SetupFrame {
        try SetupFrame.make(setup: setup(for: toolpath), stock: selectedStockMaterial)
    }

    /// For the places that only need a best guess (the suggested depth): identity when the
    /// frame can't be made, and Generate then reports why.
    private func frameOrIdentity(for toolpath: ToolpathData) -> SetupFrame {
        (try? setupFrame(for: toolpath)) ?? .identity
    }

    /// The map into the active setup, for the 3D canvas to turn the stock and model with:
    /// identity when the stock or angle can't be handled (Generate says why).
    var activeSetupFrame: SetupFrame {
        guard let setup = setups.first(where: { $0.id == activeSetupID }) else {
            return .identity
        }
        return (try? SetupFrame.make(setup: setup, stock: selectedStockMaterial)) ?? .identity
    }

    func activateSetup(_ id: UUID) {
        guard setups.contains(where: { $0.id == id }) else {
            return
        }
        activeSetupID = id
    }

    /// Adds a setup at the end and makes it the active one.
    @discardableResult
    func addSetup(face: SetupFace, axis: SetupAxis? = nil) -> UUID {
        let axis = face.hasChoiceOfAxis ? (axis ?? face.axis) : face.axis
        let setup = Setup(face: face, axis: axis,
                          name: Setup.uniqueName(for: face, axis: axis, among: Set(setups.map(\.name))))
        setups.append(setup)
        activeSetupID = setup.id
        return setup.id
    }

    func renameSetup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = setups.firstIndex(where: { $0.id == id }),
              setups[index].name != trimmed else {
            return
        }
        setups[index].name = trimmed
    }

    /// Turns a setup to another face. Its toolpaths are outdated by it (see `setups`' `didSet`).
    /// A name that was just the old face's ("Front 2" included) follows the face.
    func setSetupFace(_ id: UUID, to face: SetupFace, axis: SetupAxis? = nil) {
        let axis = face.hasChoiceOfAxis ? (axis ?? face.axis) : face.axis
        guard let index = setups.firstIndex(where: { $0.id == id }),
              setups[index].angle != face.angle || setups[index].axis != axis else {
            return
        }
        let wasDefaultName = setups[index].face.map { old in
            let base = Setup.baseName(for: old, axis: setups[index].axis)
            return setups[index].name == base || setups[index].name.hasPrefix(base + " ")
        } ?? false
        setups[index].angle = face.angle
        setups[index].axis = axis
        if wasDefaultName {
            let others = Set(setups.enumerated().filter { $0.offset != index }.map(\.element.name))
            setups[index].name = Setup.uniqueName(for: face, axis: axis, among: others)
        }
    }

    /// Which axis a flipped face turns about, i.e. which way its shapes mirror: about X they mirror
    /// in Y, about Y in X. Only the bottom has a choice. Its toolpaths are outdated by it.
    func setSetupAxis(_ id: UUID, to axis: SetupAxis) {
        guard let face = setups.first(where: { $0.id == id })?.face, face.hasChoiceOfAxis else {
            return
        }
        setSetupFace(id, to: face, axis: axis)
    }

    /// Moves a setup to `newIndex` in the machining order; its toolpaths go with it.
    func moveSetup(_ id: UUID, to newIndex: Int) {
        guard let from = setups.firstIndex(where: { $0.id == id }) else {
            return
        }
        let to = min(max(newIndex, 0), setups.count - 1)
        guard from != to else {
            return
        }
        var reordered = setups
        reordered.insert(reordered.remove(at: from), at: to)
        setups = reordered
        toolpaths = Self.orderedBySetup(toolpaths, setups: setups)
        updateToolpathPreview()
    }

    /// Deletes a setup and the toolpaths cut in it. The last one can't be deleted.
    func deleteSetup(_ id: UUID) {
        guard setups.count > 1, setups.contains(where: { $0.id == id }) else {
            return
        }
        for toolpath in toolpaths(in: id) {
            deleteToolpath(toolpath.id)
        }
        setups.removeAll { $0.id == id }
        if activeSetupID == id {
            activeSetupID = setups[0].id
        }
    }

    /// Puts saved setups back (a project was opened) and attaches the toolpaths that have none.
    /// Not a user edit, but it does report through `onSetupsChanged`.
    func restoreSetups(_ saved: [Setup]) {
        setups = saved.isEmpty ? [Setup(face: .top)] : saved
        activeSetupID = setups[0].id
        toolpaths = Self.orderedBySetup(toolpaths, setups: setups)
    }

    private static func orientations(of setups: [Setup]) -> [UUID: SetupOrientation] {
        Dictionary(setups.map { ($0.id, $0.orientation) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every toolpath in a setup that exists (the first when it has none or its setup is gone), and
    /// the list in setup order, each setup keeping the toolpaths' own order.
    private static func orderedBySetup(_ toolpaths: [ToolpathData], setups: [Setup]) -> [ToolpathData] {
        guard let first = setups.first else {
            return toolpaths
        }
        let rank = Dictionary(setups.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        var list = toolpaths
        for index in list.indices where list[index].setupID.flatMap({ rank[$0] }) == nil {
            list[index].setupID = first.id
        }
        return list.enumerated().sorted { a, b in
            let ra = a.element.setupID.flatMap { rank[$0] } ?? 0
            let rb = b.element.setupID.flatMap { rank[$0] } ?? 0
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
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

    private static func defaultToolpath() -> ToolpathData {
        var toolpath = ToolpathData(id: UUID(),
                                    name: "Contour 1",
                                    tool: Tool(id: UUID(),
                                               name: "3.175mm",
                                               shankDiameter: 3.175,
                                               toolDiameter: 3.175,
                                               cuttingHeight: 12,
                                               type: .endMill,
                                               group: nil,
                                               tipAngle: nil,
                                               presets: []),
                                    startZ: 0,
                                    endZ: -1,
                                    contour: .onContour,
                                    ramping: RampingSettings(enabled: true,
                                                             type: .linear,
                                                             angle: 2,
                                                             length: 10),
                                    feedRate: 800,
                                    plungeRate: 400,
                                    spindleRPM: 12000,
                                    stepDown: 0.1,
                                    stepOverPercent: 40,
                                    safeZ: 3)
        toolpath.applyDefaults(for: toolpath.operation.kind)
        return toolpath
    }

    // MARK: Holding tabs preview

    /// Keeps the canvas's holding tabs in step with the open toolpath: they are drawn while a
    /// contour toolpath with tabs and shapes is open, and not otherwise. A no-op while nothing
    /// changed, so it is cheap to call after any edit.
    private func syncHoldingTabs() {
        guard let id = selectedToolpathID,
              let toolpath = toolpaths.first(where: { $0.id == id }),
              toolpath.operation.kind == .contour,
              !toolpath.operation.contourTabs.isEmpty,
              !toolpath.targets.isEmpty else {
            canvasState.setHoldingTabs(nil)
            return
        }
        canvasState.setHoldingTabs(D2_CanvasState.HoldingTabsOverlay(targets: toolpath.targets,
                                                                     tabs: toolpath.operation.contourTabs))
    }

    // MARK: Shape picking

    /// Keeps the canvas's picking mode in step with the open toolpath: opening
    /// one starts picking shapes for it, switching moves picking over to the new
    /// one, closing it stops picking.
    private func syncPickingWithSelection() {
        // A rest toolpath has no shapes of its own, so nothing is picked while one is open
        let wanted = selectedToolpathID.flatMap { id in
            toolpaths.first { $0.id == id }?.operation.kind == .restMachining ? nil : id
        }
        guard pickingToolpathID != wanted else {
            return
        }
        if pickingToolpathID != nil {
            endPicking()
        }
        if let wanted {
            beginPicking(for: wanted)
        }
    }

    private func beginPicking(for id: UUID) {
        guard let toolpath = toolpaths.first(where: { $0.id == id }) else {
            return
        }
        // A rest toolpath has no shapes of its own: it is linked to a pocket
        guard toolpath.operation.kind != .restMachining else {
            return
        }
        // Set before seeding the canvas: seeding can prune stale targets and
        // report that back through applyPickedPaths, which needs this id.
        pickingToolpathID = id
        canvasState.beginPickingPaths(initial: toolpath.targets)
        // The same toolpath is picked in the 3D canvas, where the shapes are STEP edges
        stepWorkspace.beginPicking(targets: toolpath.stepTargets) { [weak self] importID, edges in
            self?.applyPickedSTEPEdges(importID: importID, edges: edges)
        }
    }

    private func endPicking() {
        pickingToolpathID = nil
        canvasState.endPickingPaths()
        stepWorkspace.endPicking()
    }

    /// The edges of one model were clicked while a toolpath is open: they are written into
    /// the toolpath live, like picked shapes. The edges of other models stay as they were.
    private func applyPickedSTEPEdges(importID: UUID, edges: Set<STEPEdgeID>) {
        guard let id = pickingToolpathID,
              let index = toolpaths.firstIndex(where: { $0.id == id }) else {
            return
        }
        let old = toolpaths[index].stepTargets
        let oldOfModel = Set(old.filter { $0.importID == importID }.map(\.edgeID))
        var updated = old.filter { $0.importID != importID || edges.contains($0.edgeID) }
        updated += edges.subtracting(oldOfModel)
            .sorted { ($0.bodyID.entityID, $0.entityID) < ($1.bodyID.entityID, $1.entityID) }
            .map(STEPEdgeTarget.init)
        guard updated != old else {
            return
        }

        var toolpath = toolpaths[index]
        toolpath.stepTargets = updated
        // End Z follows the selection until it is set by hand: it still equals the depth of
        // the previous selection, or was never set.
        let frame = frameOrIdentity(for: toolpath)
        if let depth = stepWorkspace.suggestedEndZ(for: updated, frame: frame) {
            let previous = stepWorkspace.suggestedEndZ(for: old, frame: frame)
            let followsSelection = previous.map { abs(toolpath.endZ - $0) < 1e-6 } ?? !toolpath.editedFields.contains(.endZ)
            if followsSelection {
                toolpath.endZ = depth
                toolpath.editedFields.insert(.endZ)
            }
        }
        toolpaths[index] = toolpath
    }

    // MARK: Toolpath generation

    /// Runs StratumCAM for the toolpath `id` and stores the outcome (result or
    /// error) in `generations`, where the toolpath's cell reads it from.
    ///
    /// The canvas is read here on the main thread, but the engine run and the
    /// overlay path building happen in the background; the UI stays responsive
    /// and the cell shows a spinner until `finishGeneration` applies the result.
    func generateToolpaths(for id: UUID) {
        guard let toolpath = toolpaths.first(where: { $0.id == id }), !generatingIDs.contains(id) else {
            return
        }

        let requestedAt = PerfLog.now()
        PerfLog.log("gen", "▶ Generate requested for '\(toolpath.name)' (\(canvasState.objects.count) object(s) on canvas)")

        // A rest toolpath is generated from the pocket it is linked to
        let linkedSource = toolpath.operation.restSourceID.flatMap { sourceID in
            toolpaths.first { $0.id == sourceID }
        }

        let job: ToolpathGenerator.Job
        do {
            // The stock as the machine holds it in this toolpath's setup
            let frame = try setupFrame(for: toolpath)
            job = try ToolpathGenerator.prepare(for: toolpath, source: linkedSource, canvasState: canvasState,
                                                frame: frame,
                                                stepContours: { [workspace = stepWorkspace] in
                                                    try workspace.contours(for: $0.stepTargets, frame: frame)
                                                })
        } catch {
            // Bad input (no shapes, invalid depth…): report it right away.
            PerfLog.log("gen", "prepare failed: \(ToolpathGenerator.message(for: error))")
            var failed = ToolpathGeneration(source: toolpath, outcome: .failure(error), previewPath: nil)
            failed.sourceSnapshot = linkedSource
            generations[id] = failed
            return
        }
        PerfLog.log("gen", "prepare (main thread) took \(PerfLog.fmt(PerfLog.ms(since: requestedAt)))")

        let token = UUID()
        generationTokens[id] = token
        generatingIDs.insert(id)
        let previewOptions = self.previewOptions

        Task { [weak self] in
            let computed = await Task.detached(priority: .userInitiated) { () -> ComputedGeneration in
                do {
                    let outputs = try ToolpathGenerator.run(job)
                    let pathStart = PerfLog.now()
                    // The engine ran in the setup's frame, the canvas draws the part's: map the
                    // overlays back. Front and back have no top-down view, so nothing is drawn
                    // (and the scrub slider, which has no mapping yet, is off for turned setups).
                    let frame = job.frame
                    let previewPath = frame.previewInPartFrame(ToolpathPathBuilder.path(for: outputs, options: previewOptions))
                    let scrub = frame.isIdentity ? ToolpathPathBuilder.scrubData(for: outputs, options: previewOptions) : nil
                    let restPath = frame.previewInPartFrame(ToolpathPathBuilder.restPath(for: outputs.flatMap(\.restCorners)))
                    PerfLog.log("gen", "background work finished; preview path + scrub data took \(PerfLog.fmt(PerfLog.ms(since: pathStart)))")
                    return ComputedGeneration(outcome: .success(outputs),
                                              previewPath: previewPath,
                                              scrub: scrub,
                                              restPath: restPath)
                } catch {
                    return ComputedGeneration(outcome: .failure(error), previewPath: nil, scrub: nil, restPath: nil)
                }
            }.value

            self?.finishGeneration(id: id, token: token, source: toolpath, linkedSource: linkedSource,
                                   computed: computed, requestedAt: requestedAt)
        }
    }

    private func finishGeneration(id: UUID, token: UUID, source: ToolpathData, linkedSource: ToolpathData?,
                                  computed: ComputedGeneration, requestedAt: UInt64) {
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
                                             previewPath: computed.previewPath,
                                             scrub: computed.scrub,
                                             restPath: computed.restPath,
                                             sourceSnapshot: linkedSource)
        // The pocket may have been edited while this was running
        refreshLinkedGenerations()
        PerfLog.log("gen", "◼ applied in \(PerfLog.fmt(PerfLog.ms(since: applyStart))) (state update + preview overlay); "
                    + "total click → applied: \(PerfLog.fmt(PerfLog.ms(since: requestedAt)))")
    }

    /// Shows the corners of the open pocket on the canvas: only while its result is current and
    /// the switch is on. Scrubbing doesn't hide them: an open pocket with a current result is
    /// always being scrubbed.
    private func updateRestRegions() {
        guard showsRestAreas,
              let id = selectedToolpathID,
              let toolpath = toolpaths.first(where: { $0.id == id }),
              toolpath.operation.kind == .pocket,
              let generation = generations[id],
              generation.isCurrent(for: toolpath) else {
            canvasState.setRestRegionsPath(nil)
            return
        }
        canvasState.setRestRegionsPath(generation.restPath)
    }

    /// A rest toolpath's result is outdated once the pocket it is linked to is edited or deleted.
    /// The pocket's name is ignored: renaming it changes nothing that is cut.
    private func refreshLinkedGenerations() {
        for (id, generation) in generations where generation.source.operation.kind == .restMachining {
            let current = generation.source.operation.restSourceID.flatMap { sourceID in
                toolpaths.first { $0.id == sourceID }
            }
            let outdated = !Self.sameCut(current, generation.sourceSnapshot)
            if outdated != generation.isLinkedSourceOutdated {
                generations[id]?.isLinkedSourceOutdated = outdated
            }
        }
    }

    private static func sameCut(_ a: ToolpathData?, _ b: ToolpathData?) -> Bool {
        guard var a, var b else {
            return a == nil && b == nil
        }
        a.name = ""
        b.name = ""
        return a == b
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
        // While one toolpath is being scrubbed, it is the only one on the canvas
        // (the scrubber draws it); the rest come back when the panel closes.
        // Only the active setup's toolpaths: another setup is cut with the stock turned, so its
        // overlay would sit on the wrong side of the part.
        let paths = canvasState.toolpathScrub != nil ? [] : toolpaths
            .filter { !hiddenToolpathIDs.contains($0.id) && isInActiveSetup($0) }
            .compactMap { generations[$0.id]?.previewPath }

        updateRestRegions()
        updateFaceToolpaths()

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

    /// Every setup's generated toolpaths, one group per face, for the 3D view: it shows them
    /// all whichever face is up. Each group carries the height of its face's z0 in the part's
    /// frame, so the canvas puts it on that face and the turn to the active face does the rest.
    private func updateFaceToolpaths() {
        guard canvasState.toolpathScrub == nil else {
            canvasState.setFaceToolpaths([])
            return
        }
        var faces: [D2_CanvasState.FaceToolpaths] = []
        for setup in setups {
            let paths = toolpaths
                .filter { !hiddenToolpathIDs.contains($0.id) && self.setup(for: $0).id == setup.id }
                .compactMap { generations[$0.id]?.previewPath }
            guard !paths.isEmpty else {
                continue
            }
            let combined = CGMutablePath()
            paths.forEach { combined.addPath($0) }
            let frame = try? SetupFrame.make(setup: setup, stock: selectedStockMaterial)
            faces.append(.init(setupID: setup.id, face: setup.face, path: combined,
                               z: CGFloat(frame?.z0InPartFrame ?? 0)))
        }
        canvasState.setFaceToolpaths(faces)
    }

    private func isInActiveSetup(_ toolpath: ToolpathData) -> Bool {
        setups.count < 2 || setup(for: toolpath).id == activeSetupID
    }

    // MARK: Toolpath scrubbing

    /// The open toolpath's result, if it can be scrubbed: the last Generate worked,
    /// cut something, and the toolpath still matches it (an outdated result would
    /// be previewed with settings it no longer has).
    private var scrubbableGeneration: ToolpathGeneration? {
        guard let id = selectedToolpathID,
              let toolpath = toolpaths.first(where: { $0.id == id }),
              let generation = generations[id],
              generation.scrub != nil,
              generation.isCurrent(for: toolpath) else {
            return nil
        }
        return generation
    }

    /// Keeps the canvas's scrub preview in step with the open toolpath: starts it
    /// (at the end, i.e. the whole toolpath) when the open toolpath has a scrubbable
    /// result, replaces it when a new one lands, and ends it when there is none.
    /// A no-op while nothing changed, so it is cheap to call after any edit.
    private func syncScrub(refreshPreview: Bool = true) {
        let generation = scrubbableGeneration
        guard generation?.id != scrubbedGenerationID else {
            return
        }
        scrubbedGenerationID = generation?.id

        if let generation, let data = generation.scrub {
            canvasState.setToolpathScrub(D2_CanvasState.ToolpathScrub(id: generation.id,
                                                                      data: data,
                                                                      toolDiameter: generation.source.tool.toolDiameter,
                                                                      step: data.stepCount))
        } else {
            canvasState.setToolpathScrub(nil)
        }
        if refreshPreview {
            updateToolpathPreview()
        }
    }

    /// The scrub slider in the toolpath panel moved. Called on every tick of a drag.
    func setToolpathScrubStep(_ step: Int) {
        canvasState.setToolpathScrubStep(step)
    }

    private func applyPickedPaths(_ paths: [PathSelection]) {
        guard let id = pickingToolpathID,
              let index = toolpaths.firstIndex(where: { $0.id == id }) else {
            return
        }
        toolpaths[index].targets = paths
    }

    @discardableResult
    func loadAndParseFileAt(_ url: URL, restoring savedObjects: [AssetObjectData]? = nil,
                           stepImportID: UUID? = nil,
                           onSTEPFinished: @escaping @MainActor () -> Void = {}) -> D2_Object? {
        let imported: [D2_Object]
        switch url.pathExtension.lowercased() {
        case "step", "stp":
            stepWorkspace.load(STEPSourceReference(id: stepImportID ?? UUID(), name: url.lastPathComponent, url: url),
                               onFinished: onSTEPFinished)
            return nil
        case "svg": imported = SVGImporter().parse(url: url).map { [$0] } ?? []
        case "dxf": imported = DXFImporter().parse(url: url).map { [$0] } ?? []
        case "zip": imported = GerberImporter().parse(url: url)
        default: return nil
        }

        var restored: [D2_Object] = []
        for parsed in imported {
            let object: D2_Object
            if let savedObjects {
                // The saved list is authoritative: omitted archive layers were deleted.
                guard let saved = savedObjects.first(where: { $0.name == parsed.name }) else { continue }
                object = D2_Object(id: saved.id, name: parsed.name, paths: parsed.paths,
                                   entities: parsed.entities, contours: parsed.contours,
                                   position: CGPoint(x: saved.transform.x, y: saved.transform.y),
                                   originalSize: parsed.originalSize, width: max(saved.transform.width, 0.001))
                object.setRotation(saved.transform.rotation)
            } else {
                object = parsed
            }
            object.sourceAssetName = url.lastPathComponent
            restored.append(object)
            canvasState.add(object, select: false)
        }
        return restored.first
    }

    func clear() {
        stepWorkspace.clear()
        endPicking()
        discardGenerations()
        canvasState.removeAll()
        selectedToolpathID = nil
        hiddenToolpathIDs.removeAll()
        toolpaths.removeAll()
        // Back to a lone top setup (the next project restores its own, see `restoreSetups`)
        setups = [Setup(face: .top)]
        activeSetupID = setups[0].id
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
        guard let screen = screen else {
            return
        }

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
    let scrub: ToolpathScrubData?
    let restPath: CGPath?
}
