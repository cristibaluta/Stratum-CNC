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

    var allowedContentTypes: [UTType] {
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

    var activeToolSpec: ToolSpec? {
        for toolNumber in tools {
            if let spec = toolSpecAssignments[toolNumber] {
                return spec
            }
        }
        return nil
    }

    func generateGCode(for toolpath: ToolpathData, canvasState: D2_CanvasState) {
        do {
            let gcode = try ToolpathGCodeBuilder.generate(for: toolpath, canvasState: canvasState)
            document.load(from: gcode)
        } catch {
            print("G-code generation failed: \(error.localizedDescription)")
            // consider surfacing this in the UI, e.g. an @Published var lastError: String?
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
