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

    // `document` is its own `ObservableObject` (it publishes `lines`, `isLoading`,
    // etc. independently). Views here only ever observe `GCodeStore`, so without
    // this, a change to `document.lines` — e.g. finishing an async file load —
    // never triggers a re-render: `GCodeStore.objectWillChange` only fires when
    // the `document` *reference* itself is reassigned, not when its internal
    // @Published properties mutate. Forwarding its publisher closes that gap.
    private var documentCancellable: AnyCancellable?

    init() {
        bindDocument()
    }

    private func bindDocument() {
        documentCancellable = document.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
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
    func markerObject(at point: SIMD3<Float>,
                      diameter: Float = 6.0,
                      height: Float = 12.0,
                      segments: Int = 28,
                      strutCount: Int = 4,
                      color: SIMD4<Float> = SIMD4<Float>(1.0, 0.05, 0.05, 1.0)) -> RenderObject {
        RenderObject.marker(at: point,
                            diameter: diameter,
                            height: height,
                            segments: segments,
                            strutCount: strutCount,
                            color: color)
    }

    /// `buildWaypoints`/toolpath passes only carry the *endpoints* of each move (plus a
    /// center + direction for arcs) since that's all a real controller needs for `G02`/`G03`.
    /// For the on-screen preview we need actual curvature, so this walks the waypoints and,
    /// for any `arcCW`/`arcCCW` motion, inserts interpolated points along the true arc between
    /// the previous waypoint and this one instead of drawing a straight chord between them.
    /// Internal rather than `private` so a subclass in another file (e.g.
    /// `DemoSlotting`'s boundary-recognition demos, which need to build a
    /// combined result from two different contours -- the physical boundary for
    /// the blue reference, a derived centerline for the yellow toolpath -- rather
    /// than the single shared contour `run(contour:...)` assumes) can tessellate
    /// its own waypoints the same way `run(contours:...)`/`run(facing:)` do,
    /// without duplicating this arc-interpolation logic a third time.
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
