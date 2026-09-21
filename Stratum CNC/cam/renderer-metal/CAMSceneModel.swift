//
//  CAMSceneModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  The CAM counterpart of `CanvasSceneModel`, deliberately much smaller: it
//  owns nothing but `renderObjects`, rebuilt from a `D2_CanvasState`
//  snapshot whenever that state changes. `CanvasSceneModel` is
//  controller-specific (heightmap, tool, scrub state) and CAM doesn't go
//  through it. This is the "caller decides which default objects go in"
//  half of the plan's workstream A: CAM asks for stock + ruler only, never
//  the controller's work bed / anchor / axes.
//
//  Step 3 of the plan's suggested sequencing — no picking or mouse
//  interaction yet (steps 4+), so this only needs to *draw*.
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

    /// Window-background color (appearance-aware) for `MetalCanvasView.clearColor`.
    @Published private(set) var backgroundColor = SIMD4<Float>(0.2, 0.2, 0.2, 1)

    /// The per-path data from the last rebuild — world-space `CGPath` and
    /// bounds included. `CAMCanvasInteraction` hit-tests against this, so a
    /// click is resolved against exactly the geometry that's on screen,
    /// without flattening again (the plan's "cache the world-space CGPath
    /// per path alongside its RenderObject").
    private(set) var renderPaths: [D2_RenderPath] = []

    /// Fixed look for the non-path objects. Colors are muted on purpose:
    /// the ruler must not be orange (that's the "picked" color) and the
    /// stock shouldn't out-shout the shapes. Visual parity with the
    /// CoreAnimation canvas (fill tint, hatch) is the plan's step 5.
    enum Style {
        /// Same length `D2_CanvasRenderer` gives its `RulerShapeLayer`.
        static let rulerLength: Float = 200
        static let rulerColor = SIMD4<Float>(0.55, 0.55, 0.55, 1)
        static let stockColor = SIMD4<Float>(0.5, 0.5, 0.62, 1)
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
    private var rebuildScheduled = false

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

        rebuild()
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
            for object in canvasState.objects where canvasState.selectedObjectIDs.contains(object.id) {
                overlay.append(contentsOf: CAMSelectionOverlay.renderObjects(for: object,
                                                                             boxColor: boxColor,
                                                                             handleColor: handleColor))
            }
        }

        // Order matters. The renderer's depth test is `.less` and all of
        // this is at z = 0, so where two lines coincide the one drawn
        // *first* wins. Selection overlay first (the handle must be on
        // top), then shapes (the thing being selected), then the toolpath
        // preview, then the ruler, then the stock outline.
        var objects: [RenderObject] = overlay
        objects.reserveCapacity(overlay.count + paths.count + 3)
        for path in paths where !path.renderObject.points.isEmpty {
            objects.append(path.renderObject)
        }
        if let toolpath {
            objects.append(toolpath)
        }
        objects.append(.ruler(z: 0, length: Style.rulerLength, color: Style.rulerColor))
        if canvasState.isStockVisible, let stock = canvasState.stock {
            objects.append(.stockBox(for: stock, color: Style.stockColor))
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
