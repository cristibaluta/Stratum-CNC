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
import StratumCAM
import SwiftSTEP

@MainActor
class CAMModel: ObservableObject {

    // ---- PERSISTENT DATA (mirrors ProjectData) ----
    /// Bumped whenever something the generated G-code is built from changes: the
    /// toolpath settings, their generated results, or the setups. The Controller
    /// compares it with the value its program was generated at to know when that
    /// program is out of date (see `GCodeStore.generatedFromCAMRevision`).
    /// Only real changes count: a write of the value that is already there (a form
    /// writing its binding back, say) doesn't bump it. The stock isn't a source of its
    /// own: a change that reaches the cutting moves discards the affected results, and
    /// that bumps it (see `selectedStockMaterial`).
    @Published private(set) var revision = 0

    @Published var selectedStockMaterial: StockMaterial {
        didSet {
            // A write that changes nothing isn't an edit
            guard selectedStockMaterial != oldValue else {
                return
            }
            // The alignment pins are fitted to the project's stock, whatever setup is active
            canvasState.stock = selectedStockMaterial
            canvasState.refitAlignmentPins()
            // The canvas then shows the active setup's stock (the project's unless it has its own)
            syncCanvasStock()
            // Only the stock's shape and size can reach the cutting moves: a turned setup is
            // built from them, and so is a facing of the whole stock. Their results are
            // outdated then, for the setups that use the project stock (one with a stock of its
            // own doesn't care). Material, name, quantity… change nothing that is cut.
            if selectedStockMaterial.geometry != oldValue.geometry,
               setups.contains(where: { $0.stock == nil && cutsDependOnStockGeometry(in: $0) }) {
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
            if setups != oldValue {
                revision &+= 1
            }
            onSetupsChanged?(setups)
            // A setup's own stock, or another active setup, changes what the canvas shows
            syncCanvasStock()
            // So does a placement of its own for an object
            applyActivePlacement()
            // Renaming or reordering changes nothing that is cut; a different orientation does
            // The objects a setup includes, and where it places them, decide what is cut too
            if Self.orientations(of: oldValue) != Self.orientations(of: setups)
                || Self.items(of: oldValue) != Self.items(of: setups)
                || stockGeometryChanged(from: oldValue, to: setups) {
                discardGenerations()
            }
        }
    }

    /// The setup the toolpath list is looking at: "Add toolpath" adds to it, and its toolpaths are
    /// the ones drawn on the canvas. Opening a toolpath makes its setup the active one.
    @Published private(set) var activeSetupID: UUID {
        didSet {
            if oldValue != activeSetupID {
                // Changing the face closes the open toolpath, unless it belongs to the new face
                // (opening a toolpath makes its own face the active one, see `selectedToolpathID`)
                if let id = selectedToolpathID,
                   toolpaths.first(where: { $0.id == id })?.setupID != activeSetupID {
                    selectedToolpathID = nil
                }
                // Each setup can be cut from another stock: the canvas follows the active one
                syncCanvasStock()
                // ...and place the objects its own way
                applyActivePlacement()
                syncFocusToActiveSetup()
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
            if toolpaths != oldValue {
                revision &+= 1
            }
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
                // Its setup is the selection now
                if !isSetupSelected {
                    isSetupSelected = true
                }
            }
            // A toolpath and objects are never selected together
            if selectedToolpathID != nil, !canvasState.selectedObjectIDs.isEmpty {
                canvasState.clearSelection()
            }
            syncPickingWithSelection()
            syncScrub(refreshPreview: false)
            syncHoldingTabs()
            // While one is open it is the only toolpath on the canvas; with none open the canvas
            // shows none, or all of them (`showsAllToolpaths`). Also refreshes the rest areas.
            updateToolpathPreview()
            if let id = selectedToolpathID {
                generateIfNeeded(id)
            } else {
                generateAllIfNeeded()
            }
        }
    }

    /// The toolpath currently in "select shapes" mode, if any. While this is
    /// non-nil the canvas is in picking mode (canvasState.isPickingPaths) and
    /// every click on a shape adds/removes it from that toolpath's `targets`.
    @Published private(set) var pickingToolpathID: UUID?

    /// Runs the generations and keeps their results (see `ToolpathGenerationStore`). CAMModel
    /// forwards what the views and the Controller read, and reacts when the results change.
    private let generationStore = ToolpathGenerationStore()

    /// Keeps the canvas overlay and the scrub preview in step with the results.
    private let preview = ToolpathPreviewController()

    /// Result of the last "Generate" per toolpath id. Session-only.
    var generations: [UUID: ToolpathGeneration] {
        generationStore.generations
    }

    /// Toolpaths whose generation is running in the background right now.
    var generatingIDs: Set<UUID> {
        generationStore.generatingIDs
    }

    /// How generated toolpaths are drawn and previewed on this canvas (see
    /// `ToolpathGenerationStore.previewOptions`).
    var previewOptions: ToolpathPreviewOptions {
        get {
            generationStore.previewOptions
        }
        set {
            generationStore.previewOptions = newValue
        }
    }

    /// The legend's "All toolpaths": with no toolpath open, every toolpath of every setup is
    /// calculated (what has no current result yet) and drawn; the ones of a setup that is not
    /// the active one are faded. An open toolpath always wins: then only that one is shown.
    /// Session-only, like the results.
    @Published var showsAllToolpaths = false {
        didSet {
            guard oldValue != showsAllToolpaths else {
                return
            }
            if showsAllToolpaths {
                // Asking for them while their layer is switched off would show nothing
                canvasState.hiddenLayers.remove(.toolpaths)
            }
            updateToolpathPreview()
            generateAllIfNeeded()
        }
    }

    /// Draw the corners the open pocket's tool couldn't reach (see `updateRestRegions`).
    @Published var showsRestAreas = true {
        didSet {
            updateRestRegions()
        }
    }

    /// Preview only the first and the last pass of each toolpath, on the canvas and in the scrub
    /// slider, instead of every pass. Only the preview: the G-code keeps all passes. Applies to
    /// the results already on screen (they are redrawn, not generated again) and to the next ones.
    @Published var showsFirstAndLastPassOnly = false {
        didSet {
            guard oldValue != showsFirstAndLastPassOnly else {
                return
            }
            previewOptions.passes = showsFirstAndLastPassOnly ? .firstAndLast : .all
            generationStore.rebuildPreviews()
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

    let supportedFiles: [UTType] = [.svg, .dxf, .init(filenameExtension: "step")!, .init(filenameExtension: "stp")!, .init(filenameExtension: "stl")!, .zip]

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

    /// The global placement of the 2D objects the canvas shows at a setup's own placement right
    /// now. An object is only here while that is so; see `applyActivePlacement`.
    var globalPlacementShadow: [UUID: ObjectTransform] = [:]

    /// The object the Objects tree has open: its setups are listed, and the right-hand panel edits
    /// its face up, position and size. Always one of the project's objects once there is any
    /// (see `ensureDefaultSetups`).
    @Published var focusedObjectID: UUID?

    /// What the tree has selected: a setup (true) or an object (false). Never both. An object
    /// selected shows its position and size on the right; a setup shows its stock.
    @Published var isSetupSelected = false {
        didSet {
            guard oldValue != isSetupSelected else {
                return
            }
            // Toolpaths belong to the selected setup: deselecting it closes the open one
            if !isSetupSelected, selectedToolpathID != nil {
                selectedToolpathID = nil
            }
            updateToolpathPreview()
        }
    }

    /// - Parameter setups: the project's saved setups. Empty when it has none saved yet: it gets
    ///   the top, and every toolpath goes in it.
    init(selectedStockMaterial: StockMaterial, toolpaths: [ToolpathData], setups: [Setup] = []) {
        PerfLog.start()
        let initialSetups = setups.isEmpty ? [Setup(face: .top)] : setups
        self.setups = initialSetups
        self.activeSetupID = initialSetups[0].id
        self.selectedStockMaterial = selectedStockMaterial
        self.toolpaths = Self.orderedBySetup(toolpaths, setups: initialSetups)
        self.canvasState.stock = initialSetups[0].stock ?? selectedStockMaterial

        canvasState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        generationStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        generationStore.currentToolpaths = { [weak self] in
            self?.toolpaths ?? []
        }
        generationStore.onGenerationsChanged = { [weak self] in
            self?.generationsDidChange()
        }
        stepWorkspace.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // Toolpaths cut from a STEP model's edges follow its position, like an object's
//        stepWorkspace.onModelMoved = { [weak self] in self?.discardGenerations() }

        canvasState.onObjectsChanged = { [weak self] in
            guard let self else {
                return
            }
            // An edit of an object the active setup places itself belongs to that setup
            self.routeCanvasEditToActiveSetup()
            // Toolpaths are built in world space, so moving/scaling/rotating/
            // removing an object leaves every generated result stale.
            self.discardGenerations()
            // The project file keeps the global placement, never a setup's own
            self.withGlobalPlacement {
                self.onObjectsChanged?(self.canvasState.objects)
            }
        }

        // Selecting an object closes the open toolpath
        canvasState.onObjectSelected = { [weak self] in
            guard let self else {
                return
            }
            // Clicking an object on the canvas focuses it in the tree
            if self.canvasState.selectedObjectIDs.count == 1, let id = self.canvasState.selectedObjectIDs.first {
                self.focusObject(id, keepingActiveSetup: true)
            }
            guard self.selectedToolpathID != nil else {
                return
            }
            self.selectedToolpathID = nil
        }

        // Picks are written into the toolpath live, so the cell's shape count
        // updates as the user clicks and nothing is lost when the mode closes.
        canvasState.onPickedPathsChanged = { [weak self] paths in
            self?.applyPickedPaths(paths)
        }
    }

    // MARK: Toolpath list

    func addToolpath(targets: [PathSelection] = [],
                     stepTargets: [STEPEdgeTarget] = [],
                     setupID: UUID? = nil,
                     operation: SC.MachiningOperation.Kind? = nil) {

        let setupID = setupID.flatMap { id in setups.contains { $0.id == id } ? id : nil } ?? activeSetupID
        var toolpath = toolpaths.last(where: { $0.setupID == setupID }) ?? toolpaths.last ?? Self.defaultToolpath()

        toolpath.id = UUID()
        toolpath.setupID = setupID
        // A rest toolpath is tied to its pocket, so a copy of it would be one too: start from
        // the pocket's kind of operation instead.
        if toolpath.operation.isRest {
            toolpath.operation.restSourceID = nil
        }
        // The chosen operation; untouched fields take its defaults, like picking it in the panel.
        if let operation {
            toolpath.operation.kind = operation
            toolpath.applyDefaults(for: operation)
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
        // A chamfer picked through its two rails (a face): its size and side are measured off the
        // face, and it is cut from its bottom edge (the lower rail, where it meets the wall).
        // Any other selection is single edges, which are top edges (the default).
        refreshChamferEdgeZ(&toolpath)
        if toolpath.operation.kind == .chamfer, !stepTargets.isEmpty {
            if let chamfer = stepWorkspace.chamferSuggestion(for: stepTargets, frame: frameOrIdentity(for: toolpath)) {
                toolpath.operation.chamferWidth = chamfer.width
                if let side = chamfer.side {
                    toolpath.operation.chamferSide = side
                }
                toolpath.operation.chamferUsesBottomEdge = true
            } else {
                toolpath.operation.chamferUsesBottomEdge = false
            }
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
              toolpaths[index].operation.kind == .pocket,
              !toolpaths[index].operation.isRest else {
            return
        }
        let source = toolpaths[index]

        var rest = source
        rest.id = UUID()
        rest.targets = []
        rest.operation.kind = .pocket
        rest.operation.restSourceID = sourceID
        rest.operation.pocketPattern = .offset
        rest.operation.stockToLeave = 0
        rest.operation.finishingPass = false
        // One plunge to the pocket's End Z: stepdown equals the depth (both editable afterwards).
        rest.endZ = source.endZ
        rest.stepDown = max(abs(source.endZ), 0.01)
        rest.name = SC.MachiningOperation.Kind.nextName(titled: rest.operation.title, among: Set(toolpaths.map(\.name)))

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
        guard selectedToolpathID == nil else {
            return []
        }
        // Every file on the canvas can hold the selection (a click clears the others, but not an open toolpath's picks)
        return stepWorkspace.loadedScenes.flatMap { scene in
            scene.selectedEdges.sorted { ($0.bodyID.entityID, $0.entityID) < ($1.bodyID.entityID, $1.entityID) }
                .map(STEPEdgeTarget.init)
        }
    }

    /// "Add toolpath" from the canvas tooltip: a new toolpath that cuts the selected shapes
    /// (or, in the 3D canvas, the selected STEP edges).
    /// - Parameter operation: the operation picked in the tooltip's list, if it offered one.
    func addToolpathFromSelection(operation: SC.MachiningOperation.Kind? = nil) {
        let edges = stepEdgesForNewToolpath
        if !edges.isEmpty {
            addToolpath(stepTargets: edges, operation: operation)
            return
        }
        let targets = shapesForNewToolpath
        guard !targets.isEmpty else {
            return
        }
        addToolpath(targets: targets, operation: operation)
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
        generationStore.abandonRun(for: id)

        toolpaths.removeAll { $0.id == id }
        // Removing the result also refreshes the canvas overlay (see `generationsDidChange`)
        generationStore.removeResult(for: id)
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
              !toolpath.operation.isRest else {
            return
        }
        let moving = Set([id] + toolpaths.filter {
            $0.operation.isRest && $0.operation.restSourceID == id
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

    /// The stock a setup is cut from: its own, or the project's.
    func stock(for setup: Setup) -> StockMaterial {
        setup.resolvedStock(projectStock: selectedStockMaterial)
    }

    func stock(for toolpath: ToolpathData) -> StockMaterial {
        stock(for: setup(for: toolpath))
    }

    /// The stock of the active setup: what the canvas draws and the stock panel edits.
    var activeStock: StockMaterial {
        setups.first { $0.id == activeSetupID }.map { stock(for: $0) } ?? selectedStockMaterial
    }

    /// Whether the active setup has a stock of its own.
    var activeSetupHasOwnStock: Bool {
        setups.first { $0.id == activeSetupID }?.stock != nil
    }

    /// Why the active setup can't be cut from its stock, for the stock panel; nil when it can.
    var activeStockWarning: String? {
        guard let setup = setups.first(where: { $0.id == activeSetupID }),
              let face = setup.face, face.isSide, !stock(for: setup).allowsSideFaces else {
            return nil
        }
        return "\(face.title) needs a rectangular stock."
    }

    /// Writes the stock panel's edit where it belongs: into the active setup when it has a stock
    /// of its own, into the project stock otherwise (which every other setup without one follows).
    func setActiveStock(_ stock: StockMaterial) {
        if let index = setups.firstIndex(where: { $0.id == activeSetupID }), setups[index].stock != nil {
            setups[index].stock = stock
        } else {
            selectedStockMaterial = stock
        }
    }

    /// Gives a setup a stock of its own, or (nil) makes it follow the project stock again.
    func setSetupStock(_ id: UUID, to stock: StockMaterial?) {
        guard let index = setups.firstIndex(where: { $0.id == id }), setups[index].stock != stock else {
            return
        }
        setups[index].stock = stock
    }

    /// The canvas shows one stock: the active setup's.
    private func syncCanvasStock() {
        let stock = activeStock
        if canvasState.stock != stock {
            canvasState.stock = stock
        }
    }

    /// Whether what a setup cuts depends on the shape and size of its stock: a turned setup is
    /// built from it, and so is a facing of the whole stock.
    private func cutsDependOnStockGeometry(in setup: Setup) -> Bool {
        setup.angle != 0 || toolpaths.contains { $0.setupID == setup.id && $0.cutsWholeStock }
    }

    /// Whether a setup's stock changed its shape or size, which outdates that setup's results.
    private func stockGeometryChanged(from old: [Setup], to new: [Setup]) -> Bool {
        let before = Dictionary(old.map { ($0.id, stock(for: $0).geometry) }, uniquingKeysWith: { first, _ in first })
        return new.contains { setup in
            guard let previous = before[setup.id] else {
                return false
            }
            return previous != stock(for: setup).geometry && cutsDependOnStockGeometry(in: setup)
        }
    }

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
        let setup = setup(for: toolpath)
        return try SetupFrame.make(setup: setup, stock: stock(for: setup))
    }

    /// Reads the Z of a chamfer's picked STEP edges from the geometry, in the toolpath's setup frame
    /// (0 = the top of the stock), into its settings. Without STEP edges the Z is cleared, and the
    /// library's default applies (the bevel's top at the top of the stock).
    private func refreshChamferEdgeZ(_ toolpath: inout ToolpathData) {
        guard toolpath.operation.kind == .chamfer else {
            return
        }
        let heights = toolpath.stepTargets.isEmpty
            ? nil
            : stepWorkspace.chamferEdgeHeights(for: toolpath.stepTargets, frame: frameOrIdentity(for: toolpath))
        toolpath.operation.chamferUpperEdgeZ = heights?.upper
        toolpath.operation.chamferLowerEdgeZ = heights?.lower
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
        return (try? SetupFrame.make(setup: setup, stock: stock(for: setup))) ?? .identity
    }

    /// Set while the view switches to another object's setup: the canvas shows its face at once
    /// instead of flipping the stock. Not published; cleared on the next run loop turn.
    var skipsFlipAnimation = false

    /// Runs a change that may move the canvas to another object's setup, without the flip.
    func withoutFlipAnimation(_ change: () -> Void) {
        skipsFlipAnimation = true
        change()
        DispatchQueue.main.async { [weak self] in
            self?.skipsFlipAnimation = false
        }
    }

    func activateSetup(_ id: UUID) {
        guard setups.contains(where: { $0.id == id }) else {
            return
        }
        activeSetupID = id
    }

    /// Adds a setup at the end and makes it the active one. With a `stock` the setup is cut from
    /// that workpiece instead of the project's (a second material for some of the part's edges).
    /// Names only have to differ among the setups on the same stock: the dropdown tells a "Top"
    /// from a "Top (Acrylic 3 mm)".
    @discardableResult
    func addSetup(face: SetupFace, axis: SetupAxis? = nil, stock: StockMaterial? = nil) -> UUID {
        let axis = face.hasChoiceOfAxis ? (axis ?? face.axis) : face.axis
        let label = stock?.setupLabel
        let taken = Set(setups.filter { $0.stock?.setupLabel == label }.map(\.name))
        let setup = Setup(face: face,
                          axis: axis,
                          name: Setup.uniqueName(for: face, axis: axis, among: taken),
                          stock: stock)
        setups.append(setup)
        activeSetupID = setup.id
        return setup.id
    }

    /// Sets which objects a setup includes. An empty list includes every object. Placements already
    /// set for objects that stay in are kept. Outdates the setup's toolpaths (see `setups`' `didSet`).
    func setSetupObjects(_ id: UUID, to objectIDs: [UUID]) {
        guard let index = setups.firstIndex(where: { $0.id == id }) else {
            return
        }
        let kept = Dictionary(setups[index].items.map { ($0.objectID, $0.transformOverride) },
                              uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        let items = objectIDs.filter { seen.insert($0).inserted }
            .map { SetupItem(objectID: $0, transformOverride: kept[$0] ?? nil) }
        guard setups[index].items != items else {
            return
        }
        setups[index].items = items
    }

    /// Gives an object its own placement in a setup, or with nil puts it back on the global one.
    /// The object must be one the setup lists: a setup that includes everything gets its items
    /// from `setSetupObjects` first.
    func setTransformOverride(_ transform: ObjectTransform?, for objectID: UUID, inSetup id: UUID) {
        guard let index = setups.firstIndex(where: { $0.id == id }),
              let itemIndex = setups[index].items.firstIndex(where: { $0.objectID == objectID }),
              setups[index].items[itemIndex].transformOverride != transform else {
            return
        }
        setups[index].items[itemIndex].transformOverride = transform
    }

    func renameSetup(_ id: UUID, to name: String) {
        let trimmed = name.trimmed
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

    private static func items(of setups: [Setup]) -> [UUID: [SetupItem]] {
        Dictionary(setups.map { ($0.id, $0.items) }, uniquingKeysWith: { first, _ in first })
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
            toolpaths.first { $0.id == id }?.operation.isRest == true ? nil : id
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
        guard !toolpath.operation.isRest else {
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
    private func applyPickedSTEPEdges(importID: UUID, edges: Set<STEP.EdgeID>) {
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
        refreshChamferEdgeZ(&toolpath)
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

    /// Opening a toolpath calculates it, so its preview is there without pressing Generate (which
    /// stays for refreshing it after an edit). Skipped when the toolpath can't be generated yet
    /// (no shapes, a tool that can't do the operation: the same conditions that disable the
    /// button, so opening one doesn't open on an error) and when its result is still current.
    private func generateIfNeeded(_ id: UUID?) {
        guard let id,
              let toolpath = toolpaths.first(where: { $0.id == id }),
              toolpath.hasGeometry,
              toolpath.toolCompatibilityWarning == nil else {
            return
        }
        if let generation = generations[id], generation.isCurrent(for: toolpath) {
            return
        }
        generateToolpaths(for: id)
    }

    /// "All toolpaths" is on and none is open: calculates every toolpath that has no current
    /// result (the others come from the cache). Each one is generated in its own setup's frame.
    private func generateAllIfNeeded() {
        guard showsAllToolpaths, selectedToolpathID == nil else {
            return
        }
        for toolpath in toolpaths {
            generateIfNeeded(toolpath.id)
        }
    }

    private var refreshAllTask: Task<Void, Never>?

    /// Same as `generateAllIfNeeded`, a moment later and once for a burst of changes: dragging an
    /// object discards every result over and over, and they should be calculated after it settles.
    private func scheduleAllToolpathsRefresh() {
        guard showsAllToolpaths else {
            return
        }
        refreshAllTask?.cancel()
        refreshAllTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.generateAllIfNeeded()
        }
    }

    /// Runs StratumCAM for the toolpath `id`; the outcome lands in `generations`, where the
    /// toolpath's cell reads it from. The work itself is `ToolpathGenerationStore`'s.
    func generateToolpaths(for id: UUID) {
        guard let index = toolpaths.firstIndex(where: { $0.id == id }), !generatingIDs.contains(id) else {
            return
        }
        // The edge's Z is read from the geometry in the setup's current frame, which may have
        // changed since the edges were picked.
        var refreshed = toolpaths[index]
        refreshChamferEdgeZ(&refreshed)
        if refreshed.operation != toolpaths[index].operation {
            toolpaths[index] = refreshed
        }
        let toolpath = toolpaths[index]

        // A rest toolpath is generated from the pocket it is linked to
        let linkedSource = toolpath.operation.restSourceID.flatMap { sourceID in
            toolpaths.first { $0.id == sourceID }
        }
        generationStore.generate(toolpath,
                                 linkedSource: linkedSource,
                                 frame: { try self.setupFrame(for: toolpath) },
                                 stock: stock(for: toolpath),
                                 canvasState: canvasState,
                                 stepWorkspace: stepWorkspace)
    }

    /// Runs when `generations` changed: a result landed, was removed or became outdated.
    private func generationsDidChange() {
        revision &+= 1
        // The preview below depends on whether something is being scrubbed, so sort that out first
        syncScrub(refreshPreview: false)
        updateToolpathPreview()
    }

    /// Drops every result and abandons runs in flight (their tokens no longer match).
    func discardGenerations() {
        generationStore.discardAll()
        scheduleAllToolpathsRefresh()
    }

    /// A rest toolpath's result is outdated once the pocket it is linked to is edited or deleted.
    private func refreshLinkedGenerations() {
        generationStore.refreshLinked(toolpaths: toolpaths)
    }

    /// The snapshot of the state the canvas overlay is built from.
    private var previewInput: ToolpathPreviewInput {
        ToolpathPreviewInput(canvasState: canvasState,
                             toolpaths: toolpaths,
                             setups: setups,
                             activeSetupID: activeSetupID,
                             selectedToolpathID: selectedToolpathID,
                             showsAllToolpaths: showsAllToolpaths,
                             isSetupSelected: isSetupSelected,
                             showsRestAreas: showsRestAreas,
                             stock: selectedStockMaterial,
                             generations: generations)
    }

    /// Redraws the canvas's toolpath overlay (see `ToolpathPreviewController.updatePreview`).
    private func updateToolpathPreview() {
        preview.updatePreview(previewInput)
    }

    private func updateRestRegions() {
        preview.updateRestRegions(previewInput)
    }

    /// Keeps the canvas's scrub preview in step with the open toolpath (see
    /// `ToolpathPreviewController.syncScrub`). Cheap to call after any edit.
    private func syncScrub(refreshPreview: Bool = true) {
        preview.syncScrub(previewInput, refreshPreview: refreshPreview)
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
    func loadAndParseFileAt(_ url: URL,
                            restoring savedObjects: [AssetObjectData]? = nil,
                            stepImportID: UUID? = nil,
                            onSTEPFinished: @escaping @MainActor () -> Void = {}) -> D2_Object? {

        let imported: [D2_Object]

        switch url.pathExtension.lowercased() {
            case "step", "stp", "stl":
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
                guard let saved = savedObjects.first(where: { $0.name == parsed.name }) else {
                    continue
                }
                object = D2_Object(id: saved.id,
                                   name: parsed.name,
                                   paths: parsed.paths,
                                   entities: parsed.entities,
                                   contours: parsed.contours,
                                   position: CGPoint(x: saved.transform.x, y: saved.transform.y),
                                   originalSize: parsed.originalSize,
                                   width: max(saved.transform.width, 0.001))
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

    /// Call this on init or when the view moves to a new screen (see `TrueToLife.pointsPerMM`)
    func updateTrueToLifeScale(pointsPerMM: CGFloat) {
        guard pointsPerMM > 0 else {
            return
        }
        self.trueToLifeScale = pointsPerMM
    }

    func resetToTrueToLife() {
        canvasState.zoomScale = trueToLifeScale
    }
}
