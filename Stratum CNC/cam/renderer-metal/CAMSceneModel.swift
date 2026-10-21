//
//  CAMSceneModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//

import Foundation
import Combine
import AppKit
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
        /// Same length `D2_CanvasRenderer` gives its `RulerShapeLayer`.
        static let rulerLength: Float = 200
        static let rulerColor = SIMD4<Float>(0.55, 0.55, 0.55, 1)
    }

    /// Mouse handling for this scene: hit-tests against `renderPaths` and
    /// writes selection / moves back into the canvas state. Created on
    /// first use; handed to `MetalCanvasView.pointerHandler`.
    private(set) lazy var interaction = CAMCanvasInteraction(canvasState: canvasState,
                                                            renderPaths: { [weak self] in
                                                                self?.renderPaths ?? []
                                                            })

    private let canvasState: D2_CanvasState
    private var appearance: NSAppearance
    private var stateObserver: AnyCancellable?
    private var scrubStepObserver: AnyCancellable?
    private var rebuildScheduled = false

    /// The scrubbed toolpath's geometry, kept between rebuilds so its `RenderObject.id`
    /// — and so its GPU buffer — survives them: only a new generation replaces it.
    private var scrubPathCache: (id: UUID, object: RenderObject)?

    init(canvasState: D2_CanvasState, appearance: NSAppearance = NSApp.effectiveAppearance) {
        self.canvasState = canvasState
        self.appearance = appearance

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

        rebuild()
    }

    /// The scrub slider moved: narrow the drawn part of the toolpath and move the
    /// cutter. Mutates the existing objects by role instead of rebuilding the
    /// scene, so a drag doesn't re-flatten every shape on the canvas.
    private func applyScrubStep() {
        guard let scrub = canvasState.toolpathScrub else {
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
        let name: NSAppearance.Name = (scheme == .dark) ? .darkAqua : .aqua
        guard let newAppearance = NSAppearance(named: name), newAppearance.name != appearance.name else {
            return
        }
        appearance = newAppearance
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
            self.rebuild()
        }
    }

    func rebuild() {
        let t0 = PerfLog.now()

        // Dynamic system colors resolve against the *current drawing
        // appearance*, so build under the one the view is actually in.
        var paths: [D2_RenderPath] = []
        var toolpath: RenderObject?
        var background = SIMD4<Float>(0.2, 0.2, 0.2, 1)
        var overlay: [RenderObject] = []
        appearance.performAsCurrentDrawingAppearance {
            paths = D2_RenderObjectBuilder.renderPaths(for: canvasState)
            toolpath = D2_RenderObjectBuilder.toolpathRenderObject(for: canvasState)
            background = Self.rgba(NSColor.textBackgroundColor)

            // Dashed box + rotation-center handle for whichever objects
            // are selected as a whole (a selected *path* gets neither, same
            // as `D2_ObjectNode`).
            let boxColor = Self.rgba(NSColor.systemRed)
            let handleColor = Self.rgba(NSColor.systemOrange)
            for object in canvasState.objects
                where canvasState.selectedObjectIDs.contains(object.id) && object.isVisible {
                overlay.append(contentsOf: CAMSelectionOverlay.renderObjects(for: object,
                                                                             boxColor: boxColor,
                                                                             handleColor: handleColor))
            }
        }

        // The toolpath being scrubbed, if any: its cut-so-far line and the cutter marker.
        var scrubPath: RenderObject?
        var scrubMarker: RenderObject?
        if let scrub = canvasState.toolpathScrub {
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
        var objects: [RenderObject] = scrubMarker.map { [$0] } ?? []
        objects.append(contentsOf: overlay)
        objects.reserveCapacity(objects.count + paths.count + 4)
        for path in paths where !path.renderObject.points.isEmpty {
            objects.append(path.renderObject)
        }
        if let toolpath {
            objects.append(toolpath)
        }
        if let scrubPath {
            objects.append(scrubPath)
        }
        objects.append(.ruler(z: 0, length: Style.rulerLength, color: Style.rulerColor))
        if canvasState.isStockVisible, let stock = canvasState.stock {
            objects.append(.stockBox(for: stock, color: stock.material.surfaceColor))
        }

        var selectionBounds: CGRect?
        if !canvasState.isPickingPaths, !canvasState.selectedPaths.isEmpty {
            let selected = Set(canvasState.selectedPaths)
            for path in paths where selected.contains(PathSelection(objectID: path.objectID, pathIndex: path.pathIndex)) {
                selectionBounds = selectionBounds.map { $0.union(path.worldBounds) } ?? path.worldBounds
            }
        }
        if selectionWorldBounds != selectionBounds {
            selectionWorldBounds = selectionBounds
        }

        renderPaths = paths
        renderObjects = objects
        backgroundColor = background

        PerfLog.log("metal-cam", "rebuild: \(paths.count) path(s) → \(objects.count) object(s) in \(PerfLog.fmt(PerfLog.ms(since: t0)))")
    }

    private static func rgba(_ color: NSColor) -> SIMD4<Float> {
        guard let c = color.usingColorSpace(.sRGB) else {
            return SIMD4<Float>(0.2, 0.2, 0.2, 1)
        }
        return SIMD4<Float>(Float(c.redComponent), Float(c.greenComponent),
                            Float(c.blueComponent), Float(c.alphaComponent))
    }
}
