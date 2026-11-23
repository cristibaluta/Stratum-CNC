//
//  ToolpathGenerationStore.swift
//  Stratum CNC
//
//  Split out of CAMModel: runs toolpath generations in the background and keeps their results.
//  It knows nothing about CAMModel. Everything it needs comes in as a parameter, and it reports
//  changes through `onGenerationsChanged`.
//

import Foundation
import CoreGraphics
import Combine
import StratumCAM

@MainActor
final class ToolpathGenerationStore: ObservableObject {

    /// Result of the last "Generate" per toolpath id. Session-only.
    @Published private(set) var generations: [UUID: ToolpathGeneration] = [:] {
        didSet {
            onGenerationsChanged?()
        }
    }

    /// Toolpaths whose generation is running in the background right now.
    @Published private(set) var generatingIDs: Set<UUID> = []

    /// How generated toolpaths are drawn and previewed on this canvas: which passes
    /// of each one. Both canvas presets keep every pass (z layer); the all-toolpaths
    /// overlay skips passes that repeat an XY line, the scrub slider walks them all,
    /// first pass first. Read when a generation starts, so a change
    /// applies from the next Generate, not to results already on screen.
    var previewOptions: ToolpathPreviewOptions = .canvas2D

    /// Fired after `generations` changed in any way: a result landed, was removed or marked outdated.
    var onGenerationsChanged: (() -> Void)?

    /// The current toolpath list. Read when a run finishes: a rest toolpath's result depends on
    /// the pocket it is linked to, which may have been edited while the run was in flight.
    var currentToolpaths: () -> [ToolpathData] = { [] }

    /// Identifies the in-flight run per toolpath. A run only applies its result
    /// if its token is still current — otherwise it was superseded, or the
    /// objects changed underneath it and the result would be stale.
    private var tokens: [UUID: UUID] = [:]

    // MARK: Running

    /// Runs StratumCAM for `toolpath` and stores the outcome (result or error) in `generations`,
    /// where the toolpath's cell reads it from.
    ///
    /// The canvas is read here on the main thread, but the engine run and the
    /// overlay path building happen in the background; the UI stays responsive
    /// and the cell shows a spinner until `finish` applies the result.
    ///
    /// - Parameters:
    ///   - linkedSource: for a rest toolpath, the pocket it is generated from.
    ///   - makeFrame: the stock as the machine holds it in this toolpath's setup. A throw is
    ///     reported as the toolpath's result, like any other bad input.
    func generate(_ toolpath: ToolpathData,
                  linkedSource: ToolpathData?,
                  frame makeFrame: () throws -> SetupFrame,
                  canvasState: D2_CanvasState,
                  stepWorkspace: STEPWorkspace) {

        let id = toolpath.id
        let requestedAt = PerfLog.now()
        PerfLog.log("gen", "▶ Generate requested for '\(toolpath.name)' (\(canvasState.objects.count) object(s) on canvas)")

        let job: ToolpathGenerator.Job
        do {
            let frame = try makeFrame()
            job = try ToolpathGenerator.prepare(for: toolpath,
                                                source: linkedSource,
                                                canvasState: canvasState,
                                                frame: frame,
                                                stepContours: { [workspace = stepWorkspace] in

                let chamferEdge: SC.ChamferEdge? = $0.operation.kind == .chamfer
                    ? ($0.operation.chamferUsesBottomEdge ? .bottom : .top)
                    : nil

                return try workspace.contours(for: $0.stepTargets,
                                              frame: frame,
                                              chamferEdge: chamferEdge)
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
        tokens[id] = token
        generatingIDs.insert(id)
        let previewOptions = self.previewOptions

        Task { [weak self] in
            let computed = await Task.detached(priority: .userInitiated) { () -> ComputedGeneration in
                do {
                    let outputs = try ToolpathGenerator.run(job)
                    let pathStart = PerfLog.now()
                    // The engine ran in the setup's frame, the canvas draws the part's: map the
                    // overlays back. The side faces have no top-down view, so no 2D overlay; their cuts
                    // are shown in 3D through `previewLines`. (The scrub slider, which has no mapping
                    // yet, is off for turned setups.)
                    let frame = job.frame
                    let previewPath = frame.previewInPartFrame(ToolpathPathBuilder.path(for: outputs, options: previewOptions))
                    let flat = ToolpathPathBuilder.scrubData(for: outputs, options: previewOptions)
                    let scrub = frame.isIdentity ? flat : nil
                    let previewLines = flat.flatMap { frame.previewLines($0.points) }
                    let restPath = frame.previewInPartFrame(ToolpathPathBuilder.restPath(for: outputs.flatMap(\.restCorners)))

                    PerfLog.log("gen", "background work finished; preview path + scrub data took \(PerfLog.fmt(PerfLog.ms(since: pathStart)))")

                    // The same program text the export would write for this toolpath, so the
                    // time shown here is the one that ends up in the G-code header.
                    let gcode = SCGCodeEngine().generateGCode(from: outputs, settings: ToolpathGenerator.makeSettings(from: toolpath))
                    let estimatedSeconds = GCodeTimeEstimator.estimateSeconds(of: gcode)

                    return ComputedGeneration(outcome: .success(outputs),
                                              previewPath: previewPath,
                                              scrub: scrub,
                                              previewLines: previewLines,
                                              restPath: restPath,
                                              estimatedSeconds: estimatedSeconds,
                                              frame: frame)
                } catch {
                    return ComputedGeneration(outcome: .failure(error),
                                              previewPath: nil,
                                              scrub: nil,
                                              previewLines: nil,
                                              restPath: nil,
                                              estimatedSeconds: nil,
                                              frame: job.frame)
                }
            }.value

            self?.finish(id: id,
                         token: token,
                         source: toolpath,
                         linkedSource: linkedSource,
                         computed: computed,
                         requestedAt: requestedAt)
        }
    }

    private func finish(id: UUID,
                        token: UUID,
                        source: ToolpathData,
                        linkedSource: ToolpathData?,
                        computed: ComputedGeneration,
                        requestedAt: UInt64) {

        guard tokens[id] == token else {
            PerfLog.log("gen", "result for '\(source.name)' discarded (superseded, or canvas objects changed while it ran) "
                        + "after \(PerfLog.fmt(PerfLog.ms(since: requestedAt)))")
            return
        }
        tokens[id] = nil
        generatingIDs.remove(id)

        PerfLog.log("gen", "applying result on main thread — \(PerfLog.fmt(PerfLog.ms(since: requestedAt))) after the click")
        let applyStart = PerfLog.now()
        // `onGenerationsChanged` rebuilds the preview, so nothing else to do for it here.
        var generation = ToolpathGeneration(source: source,
                                            outcome: computed.outcome,
                                            previewPath: computed.previewPath,
                                            scrub: computed.scrub,
                                            previewLines: computed.previewLines,
                                            restPath: computed.restPath,
                                            estimatedSeconds: computed.estimatedSeconds,
                                            sourceSnapshot: linkedSource)
        generation.frame = computed.frame
        generations[id] = generation
        // The pocket may have been edited while this was running
        refreshLinked(toolpaths: currentToolpaths())
        PerfLog.log("gen", "◼ applied in \(PerfLog.fmt(PerfLog.ms(since: applyStart))) (state update + preview overlay); "
                    + "total click → applied: \(PerfLog.fmt(PerfLog.ms(since: requestedAt)))")
    }

    // MARK: Rebuilding the preview

    /// Redraws every result with the current `previewOptions` (which passes are drawn), from the
    /// engine output it already has: nothing is generated again, so the G-code, the time and the
    /// outdated state stay as they are. A result replaced meanwhile (a new Generate) is left alone.
    /// Each rebuilt result is a new `ToolpathGeneration`, so the scrub slider starts again from the end.
    func rebuildPreviews() {
        let options = previewOptions
        for (id, generation) in generations {
            guard case .success(let outputs) = generation.outcome else {
                continue
            }
            let frame = generation.frame
            let oldID = generation.id
            Task { [weak self] in
                let built = await Task.detached(priority: .userInitiated) { () -> RebuiltPreview in
                    let flat = ToolpathPathBuilder.scrubData(for: outputs, options: options)
                    return RebuiltPreview(previewPath: frame.previewInPartFrame(ToolpathPathBuilder.path(for: outputs, options: options)),
                                          scrub: frame.isIdentity ? flat : nil,
                                          previewLines: flat.flatMap { frame.previewLines($0.points) })
                }.value
                self?.applyRebuilt(built, for: id, replacing: oldID)
            }
        }
    }

    private func applyRebuilt(_ built: RebuiltPreview, for id: UUID, replacing oldID: UUID) {
        guard let old = generations[id], old.id == oldID else {
            return
        }
        var new = ToolpathGeneration(source: old.source,
                                     outcome: old.outcome,
                                     previewPath: built.previewPath,
                                     scrub: built.scrub,
                                     previewLines: built.previewLines,
                                     restPath: old.restPath,
                                     estimatedSeconds: old.estimatedSeconds,
                                     sourceSnapshot: old.sourceSnapshot)
        new.isLinkedSourceOutdated = old.isLinkedSourceOutdated
        new.frame = old.frame
        generations[id] = new
    }

    // MARK: Invalidating

    /// A rest toolpath's result is outdated once the pocket it is linked to is edited or deleted.
    /// The pocket's name is ignored: renaming it changes nothing that is cut.
    func refreshLinked(toolpaths: [ToolpathData]) {
        for (id, generation) in generations where generation.source.operation.isRest {
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

    /// Abandons the run in flight for `id` (its token no longer matches). The result stays.
    func abandonRun(for id: UUID) {
        tokens[id] = nil
        generatingIDs.remove(id)
    }

    /// Drops the result of `id`. Also fires `onGenerationsChanged`, which refreshes the overlay.
    func removeResult(for id: UUID) {
        if generations[id] != nil {
            generations[id] = nil
        }
    }

    /// Drops every result and abandons runs in flight (their tokens no longer match).
    func discardAll() {
        if !generations.isEmpty || !generatingIDs.isEmpty {
            PerfLog.log("gen", "discarding \(generations.count) result(s) and abandoning \(generatingIDs.count) running generation(s) "
                        + "(an object or the project changed)")
        }
        if !tokens.isEmpty {
            tokens.removeAll()
        }
        if !generatingIDs.isEmpty {
            generatingIDs.removeAll()
        }
        if !generations.isEmpty {
            generations.removeAll()
        }
    }
}

/// What a background generation hands back to the main actor.
/// `@unchecked Sendable`: the CGPath is fully built before it crosses over and is never mutated afterwards.
private struct ComputedGeneration: @unchecked Sendable {
    let outcome: Result<[SC.OutputToolpath], Error>
    let previewPath: CGPath?
    let scrub: ToolpathScrubData?
    let previewLines: [SIMD3<Float>]?
    let restPath: CGPath?
    let estimatedSeconds: Double?
    let frame: SetupFrame
}

/// A preview redrawn from an existing result (see `ToolpathGenerationStore.rebuildPreviews`).
private struct RebuiltPreview: @unchecked Sendable {
    let previewPath: CGPath?
    let scrub: ToolpathScrubData?
    let previewLines: [SIMD3<Float>]?
}
