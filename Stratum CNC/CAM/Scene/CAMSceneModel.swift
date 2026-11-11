//
//  CAMSceneModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class CAMSceneModel: ObservableObject {

    /// Everything `MetalCanvasView` should draw, back to front in the sense
    /// that matters here: see the ordering note in `rebuild()`.
    @Published private(set) var renderObjects: [RenderObject] = []

    /// World-space bounding box of the shapes selected with the mouse (the plain
    /// selection, not the shapes picked for a toolpath), or nil when none are.
    /// What the "Add toolpath" tooltip points at.
    @Published private(set) var selectionWorldBounds: CGRect?

    /// Window-background color (appearance-aware) for `MetalCanvasView.clearColor`.
    @Published private(set) var backgroundColor = SIMD4<Float>(0.2, 0.2, 0.2, 1)

    /// The per-path data from the last rebuild — world-space `CGPath` and
    /// bounds included. `CAMCanvasInteraction` hit-tests against this, so a
    /// click is resolved against exactly the geometry that's on screen,
    /// without flattening again (the plan's "cache the world-space CGPath
    /// per path alongside its RenderObject").
    private(set) var renderPaths: [D2_RenderPath] = []

    /// Fixed look for the non-path objects. The ruler stays a muted fixed
    /// gray on purpose (it must not be orange, that's the "picked" color),
    /// but the stock box's color now comes from the selected stock
    /// material itself — see `rebuild()` — so it matches the same material
    /// swatch the controller's 3D stock and `StockPreviewView` use
    /// (`StockMaterialType.surfaceColor`), rather than one fixed tint no
    /// matter what material is picked.
    enum Style {
        /// Ruler length when there is no stock; `D2_CanvasRenderer` gives its `RulerShapeLayer` the same.
        static let defaultRulerLength: Float = 200

        /// The ruler's X and Y lengths: the stock's own width and height, so it ends at the stock's
        /// edges. Never shorter than 10 mm; 200 mm when there is no stock.
        static func rulerLengths(for stock: StockMaterial?) -> SIMD2<Float> {
            guard let stock else { return SIMD2<Float>(repeating: defaultRulerLength) }
            let size = stock.footprintSize
            let x = Float(size.width), y = Float(size.height)
            guard x.isFinite, y.isFinite, x > 0, y > 0 else { return SIMD2<Float>(repeating: defaultRulerLength) }
            return SIMD2<Float>(max(10, x), max(10, y))
        }

        static let rulerColor = SIMD4<Float>(0.55, 0.55, 0.55, 1)

        /// The toolpaths of each face, so they can be told apart in the 3D view. Top keeps the
        /// canvas's usual blue.
        static func toolpathColor(for face: SetupFace?) -> SIMD4<Float> {
            switch face {
                case .top?:    return SIMD4<Float>(0.2, 0.5, 1.0, 1)
                case .front?:  return SIMD4<Float>(0.25, 0.8, 0.4, 1)
                case .bottom?: return SIMD4<Float>(1.0, 0.6, 0.15, 1)
                case .back?:   return SIMD4<Float>(0.75, 0.4, 1.0, 1)
                case .left?:   return SIMD4<Float>(0.2, 0.8, 0.85, 1)
                case .right?:  return SIMD4<Float>(1.0, 0.4, 0.6, 1)
                case nil:      return SIMD4<Float>(0.9, 0.85, 0.2, 1)
            }
        }
    }

    /// `renderObjects` as the canvas should draw it: the flat scene with its ruler (which
    /// sits at the stock's top face, z = 0) swapped for one at the stock's *bottom* face, where
    /// the real anchor and ruler are, plus the XYZ axes gizmo marking 0, 0, 0 at the top of the
    /// stock.
    ///
    /// `frame` is the active setup's: the canvas turns the stock and model with it (see
    /// `MetalCanvasView.partTransform`), so the face that is up is z = 0 and the physical bottom
    /// is the stock's thickness below. The ruler and axes belong to the machine and are not
    /// turned, which is what keeps the origin where it was.
    ///
    /// Computed from the published `renderObjects`, so a scene change or a scrub tick refreshes
    /// it for free. The swapped-in objects are cached per bottom Z so they keep their
    /// `RenderObject.id` — and so their GPU buffers — instead of being re-uploaded on every read.
    func renderObjects3D(frame: SetupFrame = .identity) -> [RenderObject] {
        let bottomZ = frame.bottomZ ?? canvasState.stock.map { RenderObject.bottomZ(of: $0) } ?? 0
        let rulerLengths = Style.rulerLengths(for: canvasState.stock)
        if fixtures3DCache?.bottomZ != bottomZ || fixtures3DCache?.rulerLengths != rulerLengths {
            fixtures3DCache = (bottomZ: bottomZ, rulerLengths: rulerLengths,
                               objects: [.ruler(z: bottomZ, length: rulerLengths.x, lengthY: rulerLengths.y, color: Style.rulerColor)]
                                        + RenderObject.axes())
        }
        // The 2D scene's toolpath is the active face's only: the 3D view shows every face's,
        // each in its own color and on its own face (`faceToolpathObjects`).
        let objects = renderObjects.filter { $0.role != .ruler && $0.id != planarToolpathID }
            + faceToolpathObjects
            + (fixtures3DCache?.objects ?? [])

        // The anchor (its ruler) and the axes are tagged by role, so the objects list can switch
        // them off here; the shapes and toolpaths are left out when the scene is built (`rebuild`).
        let hidden = canvasState.hiddenLayers
        guard !hidden.isEmpty else {
            return objects
        }
        return objects.filter { object in
            guard let role = object.role else {
                return true
            }
            return !hidden.contains { $0.roles.contains(role) }
        }
    }

    /// Every face's toolpaths for the 3D view, built with the scene (see `rebuild`).
    private var faceToolpathObjects: [RenderObject] = []
    /// The 2D scene's own toolpath object, which the 3D view leaves out.
    private var planarToolpathID: UUID?

    private var fixtures3DCache: (bottomZ: Float, rulerLengths: SIMD2<Float>, objects: [RenderObject])?

    /// Mouse handling for this scene: hit-tests against `renderPaths` and
    /// writes selection / moves back into the canvas state. Created on
    /// first use; handed to `MetalCanvasView.pointerHandler`.
    private(set) lazy var interaction = CAMCanvasInteraction(canvasState: canvasState,
                                                            renderPaths: { [weak self] in
                                                                self?.renderPaths ?? []
                                                            })

    private let canvasState: D2_CanvasState
    private var colorScheme: ColorScheme
    private var stateObserver: AnyCancellable?
    private var scrubStepObserver: AnyCancellable?
    private var rebuildScheduled = false
    /// A drag already rebuilt the scene synchronously; the pending coalesced rebuild is redundant.
    private var rebuiltDuringDrag = false

    /// The scrubbed toolpath's geometry, kept between rebuilds so its `RenderObject.id`
    /// — and so its GPU buffer — survives them: only a new generation replaces it.
    private var scrubPathCache: (id: UUID, object: RenderObject)?

    init(canvasState: D2_CanvasState, colorScheme: ColorScheme = STAppearance.systemScheme) {
        self.canvasState = canvasState
        self.colorScheme = colorScheme

        // `objectWillChange` fires *before* the mutation lands, and often
        // several times per user action (selection + picking + ...). Hop to
        // the next main-actor turn — the mutation is complete by then — and
        // coalesce the burst into one rebuild.
        stateObserver = canvasState.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleRebuild()
            }

        // Moving the scrub slider doesn't rebuild anything (see `applyScrubStep`)
        scrubStepObserver = canvasState.toolpathScrubStepChanged
            .sink { [weak self] _ in
                self?.applyScrubStep()
            }

        // Dragging objects on the canvas: rebuild right away (the state has already
        // changed by the time this is called) so the canvas follows the cursor in
        // real time, rather than one deferred turn behind it.
        interaction.onSelectionMoved = { [weak self] in
            guard let self else {
                return
            }
            self.rebuild()
            self.rebuiltDuringDrag = true
        }
        interaction.liveObjects = { [weak self] in
            self?.renderObjects ?? []
        }

        rebuild()
    }

    /// The scrub slider moved: narrow the drawn part of the toolpath and move the
    /// cutter. Mutates the existing objects by role instead of rebuilding the
    /// scene, so a drag doesn't re-flatten every shape on the canvas.
    private func applyScrubStep() {
        guard let scrub = canvasState.toolpathScrub,
              !canvasState.hiddenLayers.contains(.toolpaths) else {
            return
        }
        // One assignment, so the canvas is told once per tick rather than twice
        var objects = renderObjects
        objects.settingVisibleVertexCount(scrub.visibleVertexCount, forRole: .toolpathCutting)
        objects.updating(CAMToolpathScrubOverlay.marker(at: scrub.toolPosition, diameter: scrub.toolDiameter))
        renderObjects = objects
    }

    /// The path colors (`labelColor` etc.) are dynamic and get baked into
    /// vertex data, so a light/dark switch needs a rebuild — the view
    /// calls this from its `colorScheme` change.
    func setColorScheme(_ scheme: ColorScheme) {
        guard scheme != colorScheme else {
            return
        }
        colorScheme = scheme
        rebuild()
    }

    private func scheduleRebuild() {
        guard !rebuildScheduled else {
            return
        }
        rebuildScheduled = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.rebuildScheduled = false
            if self.rebuiltDuringDrag {
                self.rebuiltDuringDrag = false
                return
            }
            self.rebuild()
        }
    }

    func rebuild() {
        let t0 = PerfLog.now()

        // What the person switched off in the objects list is not built at all, so it is neither
        // drawn nor hit-tested (`CAMLayersOverlay`)
        let hiddenLayers = canvasState.hiddenLayers
        let showsShapes = !hiddenLayers.contains(.shapes)
        let showsToolpaths = !hiddenLayers.contains(.toolpaths)

        // Dynamic system colors resolve against the *current drawing
        // appearance*, so build under the one the view is actually in.
        var paths: [D2_RenderPath] = []
        var toolpath: RenderObject?
        var restRegions: RenderObject?
        var background = SIMD4<Float>(0.2, 0.2, 0.2, 1)
        var overlay: [RenderObject] = []
        STAppearance.perform(as: colorScheme) {
            paths = D2_RenderObjectBuilder.renderPaths(for: canvasState)
            if showsToolpaths {
                toolpath = D2_RenderObjectBuilder.toolpathRenderObject(for: canvasState)
                restRegions = D2_RenderObjectBuilder.restRegionsRenderObject(for: canvasState)
            }
            // Flat 2D content is tagged (see `.faceOverlay`) so the 3D canvas projects it onto the
            // face that is up instead of carrying it along with the stock
            restRegions?.role = .faceOverlay
            background = Self.rgba(STColor.stTextBackground)

            // Dashed box + rotation-center handle for whichever objects
            // are selected as a whole (a selected *path* gets neither, same
            // as `D2_ObjectNode`).
            let boxColor = Self.rgba(STColor.systemRed)
            let handleColor = Self.rgba(STColor.systemOrange)
            for object in canvasState.objects
                where showsShapes && canvasState.selectedObjectIDs.contains(object.id) && object.isVisible {
                overlay.append(contentsOf: CAMSelectionOverlay.renderObjects(for: object,
                                                                             boxColor: boxColor,
                                                                             handleColor: handleColor))
            }

            // The open contour toolpath's holding tabs, drawn along the shapes it cuts
            if showsToolpaths, let tabs = canvasState.holdingTabs {
                overlay.append(contentsOf: CAMHoldingTabsOverlay.renderObjects(for: tabs,
                                                                               paths: paths,
                                                                               color: Self.rgba(STColor.systemPurple)))
            }
        }

        // The toolpath being scrubbed, if any: its cut-so-far line and the cutter marker.
        var scrubPath: RenderObject?
        var scrubMarker: RenderObject?
        if showsToolpaths, let scrub = canvasState.toolpathScrub {
            var object: RenderObject
            if let cached = scrubPathCache, cached.id == scrub.id {
                object = cached.object
            } else {
                object = CAMToolpathScrubOverlay.pathObject(for: scrub.data)
                scrubPathCache = (id: scrub.id, object: object)
            }
            object.visibleVertexCount = scrub.visibleVertexCount
            scrubPath = object
            scrubMarker = CAMToolpathScrubOverlay.marker(at: scrub.toolPosition, diameter: scrub.toolDiameter)
        } else {
            scrubPathCache = nil
        }

        // Order matters. The renderer's depth test is `.less` and all of
        // this is at z = 0, so where two lines coincide the one drawn
        // *first* wins. Selection overlay first (the handle must be on
        // top), then shapes (the thing being selected), then the toolpath
        // preview, then the ruler, then the stock outline.
        // (The cutter marker goes first of all, so it is on top.)
        func flat(_ object: RenderObject) -> RenderObject {
            var tagged = object
            tagged.role = tagged.role ?? .faceOverlay
            return tagged
        }
        var objects: [RenderObject] = scrubMarker.map { [$0] } ?? []
        objects.append(contentsOf: overlay.map(flat))
        objects.reserveCapacity(objects.count + paths.count + 4)
        for path in paths where showsShapes && !path.renderObject.points.isEmpty {
            objects.append(flat(path.renderObject))
        }
        if let toolpath {
            objects.append(toolpath)
        }
        if let restRegions {
            objects.append(restRegions)
        }
        if let scrubPath {
            objects.append(scrubPath)
        }
        let rulerLengths = Style.rulerLengths(for: canvasState.stock)
        objects.append(.ruler(z: 0, length: rulerLengths.x, lengthY: rulerLengths.y, color: Style.rulerColor))
        if canvasState.isStockVisible, let stock = canvasState.stock {
            objects.append(.stockBox(for: stock, color: stock.material.surfaceColor))
        }

        planarToolpathID = toolpath?.id
        faceToolpathObjects = (showsToolpaths ? canvasState.faceToolpaths : []).compactMap { group -> RenderObject? in
            let color = Style.toolpathColor(for: group.face)
            if let object = D2_RenderObjectBuilder.toolpathRenderObject(lines: group.lines, z: Float(group.z), color: color) {
                return object
            }
            return D2_RenderObjectBuilder.toolpathRenderObject(path: group.path, z: Float(group.z), color: color)
        }

        // Hidden shapes can't be clicked, and the "Add toolpath" tooltip has nothing to point at
        let hitPaths = showsShapes ? paths : []
        var selectionBounds: CGRect?
        if !canvasState.isPickingPaths, !canvasState.selectedPaths.isEmpty {
            let selected = Set(canvasState.selectedPaths)
            for path in hitPaths where selected.contains(PathSelection(objectID: path.objectID, pathIndex: path.pathIndex)) {
                selectionBounds = selectionBounds.map { $0.union(path.worldBounds) } ?? path.worldBounds
            }
        }
        if selectionWorldBounds != selectionBounds {
            selectionWorldBounds = selectionBounds
        }

        renderPaths = hitPaths
        renderObjects = objects
        backgroundColor = background

        PerfLog.log("metal-cam", "rebuild: \(paths.count) path(s) → \(objects.count) object(s) in \(PerfLog.fmt(PerfLog.ms(since: t0)))")
    }

    static func rgba(_ color: STColor) -> SIMD4<Float> {
        color.stRGBA
    }
}
