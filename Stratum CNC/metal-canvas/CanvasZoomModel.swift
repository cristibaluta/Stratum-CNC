//
//  CanvasZoomModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 22.10.2026.
//


//
//  CanvasZoomModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 22.09.2026.
//

import Foundation
import Combine
import simd

/// Bridges a `CanvasZoomButton` to the `MetalCanvasView` it controls. One
/// instance per canvas — CAM's locked 2D view and the controller's free 3D
/// view each own their own, same as they each own their own `Camera`.
///
/// The camera stays private to `MetalCanvasView.Coordinator`, so neither side
/// reaches into the other's internals: `MetalCanvasView` writes `percent`
/// after every frame it draws (interaction, resize, or the initial auto-fit —
/// see `MetalRenderer.onFrameRendered`) via `updatePercent`, and installs
/// `resetAction` once its camera exists so `resetToTrueToLife()` has
/// something to call. This object never sees a `Camera` or an `NSView`.
@MainActor
final class CanvasZoomModel: ObservableObject {

    /// Current zoom as a percentage of true-to-life size — 100 means 1 mm on
    /// the workpiece renders as 1 physical mm on screen (see
    /// `NSScreen.trueToLifeZoomScale`). Read by `CanvasZoomButton` to show
    /// the current level whenever it isn't 100%.
    @Published private(set) var percent: Double = 100

    /// Installed by `MetalCanvasView.makeNSView`; `nil` until the canvas has
    /// a camera to act on, so a tap before then is just a no-op rather than
    /// a crash.
    private var resetAction: (() -> Void)?

    /// Whether the current zoom is close enough to true-to-life that the
    /// button should read as "active" and the percentage readout should
    /// hide. A tolerance rather than an exact match: once nudged away from a
    /// `resetToTrueToLife()` call, floating-point zoom (drag/scroll/pinch)
    /// essentially never lands on exactly 100 again even when it looks right
    /// on screen.
    var isTrueToLife: Bool {
        abs(percent - 100) < 0.5
    }

    /// Jumps the canvas back to true-to-life size. A no-op until the canvas
    /// has installed `resetAction`.
    func resetToTrueToLife() {
        resetAction?()
    }

    /// Called only by `MetalCanvasView.Coordinator`, once per frame drawn.
    func updatePercent(_ value: Double) {
        percent = value
    }

    // MARK: Viewport (for views anchored to a spot on the canvas)

    /// Fires after every frame the canvas draws, i.e. after any pan, zoom or
    /// resize. Deliberately a plain subject rather than a `@Published`: only
    /// the few views that follow a point on the canvas (see
    /// `CAM_Metal_View`'s "Add toolpath" tooltip) subscribe, so the rest of
    /// the screen isn't re-evaluated on every pan tick.
    let frameRendered = PassthroughSubject<Void, Never>()

    /// Installed by `MetalCanvasView.makeNSView`; `nil` until the canvas has a camera.
    private var projection: ((CGPoint) -> CGPoint?)?

    /// Where a world point (mm, z = 0) currently is on screen, as fractions of
    /// the canvas size: x from 0 (left) to 1 (right), y from 0 (top) to 1
    /// (bottom) — the SwiftUI convention, so multiply by the size of a view
    /// that covers the canvas. Outside 0...1 means off screen. `nil` until the
    /// canvas has a camera.
    func normalizedViewPoint(forWorld point: CGPoint) -> CGPoint? {
        projection?(point)
    }

    /// Same as the `CGPoint` version, for a point at any height — the
    /// controller's free 3D view needs it, since a point's height shifts it
    /// on screen once the camera is orbited away from top-down.
    func normalizedViewPoint(forWorld point: SIMD3<Float>) -> CGPoint? {
        projection3D?(point)
    }

    private var projection3D: ((SIMD3<Float>) -> CGPoint?)?

    /// Called only by `MetalCanvasView.makeNSView`.
    func installProjection3D(_ projection: @escaping (SIMD3<Float>) -> CGPoint?) {
        projection3D = projection
    }

    /// Called only by `MetalCanvasView.makeNSView`.
    func installProjection(_ projection: @escaping (CGPoint) -> CGPoint?) {
        self.projection = projection
    }

    /// Called only by `MetalCanvasView.makeNSView`.
    func installResetAction(_ action: @escaping () -> Void) {
        resetAction = action
    }
}
