//
//  ToolpathPreviewController.swift
//  Stratum CNC
//
//  Split out of CAMModel: keeps the canvas's toolpath overlay, rest areas, 3D face toolpaths and
//  scrub preview in step with the generation results. It holds no model state of its own beyond
//  two caches. What it needs to know is handed in as a `ToolpathPreviewInput` on every call.
//

import Foundation
import CoreGraphics

/// A snapshot of the model state the preview is built from.
struct ToolpathPreviewInput {

    let canvasState: D2_CanvasState
    let toolpaths: [ToolpathData]
    let setups: [Setup]
    let activeSetupID: UUID
    let selectedToolpathID: UUID?
    /// The legend's "All toolpaths" (see `CAMModel.showsAllToolpaths`)
    let showsAllToolpaths: Bool
    /// Draw the corners the open pocket's tool couldn't reach
    let showsRestAreas: Bool
    let stock: StockMaterial
    let generations: [UUID: ToolpathGeneration]

    /// The toolpath's setup. A toolpath whose setup is gone (it was saved without setups) is in the first.
    func setup(for toolpath: ToolpathData) -> Setup {
        setups.first { $0.id == toolpath.setupID } ?? setups[0]
    }

    /// Whether `toolpath`'s result is on the canvas now: the open toolpath, or every one when none
    /// is open and `showsAllToolpaths` is on.
    func isShownOnCanvas(_ toolpath: ToolpathData) -> Bool {
        if let selectedToolpathID {
            return toolpath.id == selectedToolpathID
        }
        return showsAllToolpaths
    }

    func isInActiveSetup(_ toolpath: ToolpathData) -> Bool {
        setups.count < 2 || setup(for: toolpath).id == activeSetupID
    }

    /// The open toolpath's result, if it can be scrubbed: the last Generate worked,
    /// cut something, and the toolpath still matches it (an outdated result would
    /// be previewed with settings it no longer has).
    var scrubbableGeneration: ToolpathGeneration? {
        guard let id = selectedToolpathID,
              let toolpath = toolpaths.first(where: { $0.id == id }),
              let generation = generations[id],
              generation.scrub != nil,
              generation.isCurrent(for: toolpath) else {
            return nil
        }
        return generation
    }
}

@MainActor
final class ToolpathPreviewController {

    /// Which generation the canvas is scrubbing right now (see `syncScrub`).
    private var scrubbedGenerationID: UUID?

    /// Per setup: the combined preview path and 3D lines built from the generations in `key`.
    /// `updatePreview` runs after many kinds of edits; without this each run re-flattened
    /// every result's lines (a multi-MB copy for a big pocket).
    private var faceGeometryCache: [UUID: (key: [UUID], path: CGPath, lines: [SIMD3<Float>])] = [:]

    // MARK: Overlay

    /// Redraws the canvas's toolpath overlay: the open toolpath's result and nothing else, or,
    /// with none open and `showsAllToolpaths` on, every toolpath's. With neither the canvas shows none. Also runs when results are cleared
    /// (object edited, project cleared), which removes the overlay.
    func updatePreview(_ input: ToolpathPreviewInput) {
        let t0 = PerfLog.now()
        defer {
            PerfLog.log("gen", "updateToolpathPreview took \(PerfLog.fmt(PerfLog.ms(since: t0)))")
        }
        // While the open toolpath is being scrubbed, the scrubber draws it instead.
        // Only the active setup's: another setup is cut with the stock turned, so its overlay
        // would sit on the wrong side of the part (opening a toolpath makes its setup the active one).
        let paths = input.canvasState.toolpathScrub != nil ? [] : input.toolpaths
            .filter { input.isShownOnCanvas($0) && input.isInActiveSetup($0) }
            .compactMap { input.generations[$0.id]?.previewPath }

        updateRestRegions(input)
        updateFaceToolpaths(input)

        switch paths.count {
            case 0:
                input.canvasState.setToolpathsPath(nil)
            case 1:
                input.canvasState.setToolpathsPath(paths[0])
            default:
                let combined = CGMutablePath()
                paths.forEach { combined.addPath($0) }
                input.canvasState.setToolpathsPath(combined)
        }
    }

    /// Shows the corners of the open pocket on the canvas: only while its result is current and
    /// the switch is on. Scrubbing doesn't hide them: an open pocket with a current result is
    /// always being scrubbed.
    func updateRestRegions(_ input: ToolpathPreviewInput) {
        guard input.showsRestAreas,
              let id = input.selectedToolpathID,
              let toolpath = input.toolpaths.first(where: { $0.id == id }),
              toolpath.operation.kind == .pocket,
              !toolpath.operation.isRest,
              let generation = input.generations[id],
              generation.isCurrent(for: toolpath) else {

            input.canvasState.setRestRegionsPath(nil)
            return
        }
        input.canvasState.setRestRegionsPath(generation.restPath)
    }

    /// The shown toolpaths' results for the 3D view (the open toolpath's, or all of them), as one
    /// group per setup's face, faded when that setup is not the active one. A group carries the
    /// height of its face's z0 in the part's frame, so the canvas puts it on that face and the
    /// turn to the active face does the rest.
    private func updateFaceToolpaths(_ input: ToolpathPreviewInput) {
        guard input.canvasState.toolpathScrub == nil else {
            input.canvasState.setFaceToolpaths([])
            return
        }
        var faces: [D2_CanvasState.FaceToolpaths] = []
        var seenSetups = Set<UUID>()
        defer {
            if faceGeometryCache.count != seenSetups.count {
                faceGeometryCache = faceGeometryCache.filter { seenSetups.contains($0.key) }
            }
        }
        for setup in input.setups {
            let results = input.toolpaths
                .filter { input.isShownOnCanvas($0) && input.setup(for: $0).id == setup.id }
                .compactMap { input.generations[$0.id] }
            let key = results.map(\.id)
            let cached: (key: [UUID], path: CGPath, lines: [SIMD3<Float>])
            if let hit = faceGeometryCache[setup.id], hit.key == key {
                // Same generations as last time: reuse the combined path and the (large) line
                // array instead of copying hundreds of thousands of points again
                cached = hit
            } else {
                // The front, back, left and right have no 2D path (no top-down view), only 3D lines
                let paths = results.compactMap(\.previewPath)
                // The 3D view draws the lines with their Z, so every pass shows at its own depth
                let lines = results.compactMap(\.previewLines).flatMap { $0 }
                guard !paths.isEmpty || !lines.isEmpty else {
                    continue
                }
                let combined = CGMutablePath()
                paths.forEach { combined.addPath($0) }
                cached = (key: key, path: combined, lines: lines)
                faceGeometryCache[setup.id] = cached
            }
            seenSetups.insert(setup.id)
            let combined = cached.path
            let lines = cached.lines
            let frame = try? SetupFrame.make(setup: setup, stock: input.stock)
            faces.append(.init(setupID: setup.id, face: setup.face, path: combined,
                               z: CGFloat(frame?.z0InPartFrame ?? 0),
                               lines: lines, linesKey: results.map(\.id),
                               opacity: setup.id == input.activeSetupID ? 1 : CAMSceneModel.Style.inactiveSetupToolpathOpacity))
        }
        input.canvasState.setFaceToolpaths(faces)
    }

    // MARK: Scrubbing

    /// Keeps the canvas's scrub preview in step with the open toolpath: starts it
    /// (at the end, i.e. the whole toolpath) when the open toolpath has a scrubbable
    /// result, replaces it when a new one lands, and ends it when there is none.
    /// A no-op while nothing changed, so it is cheap to call after any edit.
    func syncScrub(_ input: ToolpathPreviewInput, refreshPreview: Bool = true) {
        let generation = input.scrubbableGeneration
        guard generation?.id != scrubbedGenerationID else {
            return
        }
        scrubbedGenerationID = generation?.id

        if let generation, let data = generation.scrub {
            input.canvasState.setToolpathScrub(D2_CanvasState.ToolpathScrub(id: generation.id,
                                                                            data: data,
                                                                            tool: generation.source.tool,
                                                                            step: data.stepCount))
        } else {
            input.canvasState.setToolpathScrub(nil)
        }
        if refreshPreview {
            updatePreview(input)
        }
    }
}
