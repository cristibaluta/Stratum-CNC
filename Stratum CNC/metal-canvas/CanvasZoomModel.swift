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
@MainActor
final class CanvasZoomModel: ObservableObject {

    /// Current zoom as a percentage of true-to-life size — 100 means 1 mm on the workpiece renders as 1 physical mm on screen
    @Published private(set) var percent: Double = 100

    private var resetAction: (() -> Void)?
    private var projection: ((CGPoint) -> CGPoint?)?
    private var projection3D: ((SIMD3<Float>) -> CGPoint?)?

    var isTrueToLife: Bool {
        abs(percent - 100) < 0.5
    }

    func resetToTrueToLife() {
        resetAction?()
    }

    /// Called only by `MetalCanvasView.Coordinator`, once per frame drawn.
    func updatePercent(_ value: Double) {
        guard abs(value - percent) > 0.001 else {
            return
        }
        percent = value
    }

    // MARK: Viewport (for views anchored to a spot on the canvas)

    /// Fires after every frame the canvas draws, i.e. after any pan, zoom or
    /// resize. Deliberately a plain subject rather than a `@Published`: only
    /// the few views that follow a point on the canvas (see
    /// `CAM_Metal_View`'s "Add toolpath" tooltip) subscribe, so the rest of
    /// the screen isn't re-evaluated on every pan tick.
    let frameRendered = PassthroughSubject<Void, Never>()

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


    func installProjection3D(_ projection: @escaping (SIMD3<Float>) -> CGPoint?) {
        projection3D = projection
    }

    func installProjection(_ projection: @escaping (CGPoint) -> CGPoint?) {
        self.projection = projection
    }

    func installResetAction(_ action: @escaping () -> Void) {
        resetAction = action
    }
}
