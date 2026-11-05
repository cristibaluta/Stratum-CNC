//
//  CAMCanvasInteraction.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  Mouse handling for the CAM canvas, which is always the free 3D camera: shapes are drawn
//  flat at z = 0 and are picked by intersecting the camera ray with that plane.
//
//  - a click (press and release without moving) selects the shape under it; the owner
//    (`CAM_Metal_View`) decides between shapes and STEP edges, using `shapeHit(at:)` and
//    `select(_:extend:)`
//  - any other drag orbits / pans the camera, except one that starts on the rotation-center
//    handle of a selected object, which moves the selection (`pointerDown` -> `.handled`)
//  - the handle of the STEP model selected in the objects list moves that model the same way
//  - Shift or Cmd extends/toggles the selection; an empty-space click clears it only without those
//  - while picking shapes for a toolpath, clicks toggle picks instead of changing the selection
//

import Foundation
import CoreGraphics

@MainActor
final class CAMCanvasInteraction: CanvasPointerHandler {

    /// Screen points, like `PathHitTester.tolerance`.
    private static let rotationCenterHitRadius: CGFloat = 10

    private let canvasState: D2_CanvasState
    /// Reads the *current* per-path geometry from the scene model, so a hit
    /// is tested against exactly what was last drawn.
    private let renderPaths: () -> [D2_RenderPath]
    private let hitTester = PathHitTester(tolerance: 6)

    /// Called right after a drag moved the selection, so the scene can rebuild at once.
    var onSelectionMoved: (() -> Void)?
    /// The scene's current geometry; see `CanvasPointerHandler.liveRenderObjects`.
    var liveObjects: (() -> [RenderObject])?
    private var didMoveInThisEvent = false

    private var isMovingSelection = false
    private var lastDragWorldPoint: CGPoint?

    /// The STEP model selected in the objects list: its id and where its handle sits (the middle
    /// of its footprint, in canvas mm). Set by the owner; `nil` when no model is selected.
    var stepModelHandle: (id: UUID, center: CGPoint)?
    /// A drag on the model's handle moved it by this much (canvas mm).
    var onStepModelMoved: ((UUID, CGFloat, CGFloat) -> Void)?
    private var movingStepModelID: UUID?

    init(canvasState: D2_CanvasState, renderPaths: @escaping () -> [D2_RenderPath]) {
        self.canvasState = canvasState
        self.renderPaths = renderPaths
    }

    // MARK: Clicks

    /// A toolpath is open: clicks toggle its shapes instead of selecting.
    var isPicking: Bool { canvasState.isPickingPaths }

    /// The shape under the pointer, if any.
    func shapeHit(at event: CanvasPointerEvent) -> PathSelection? {
        hitTester.hitTest(worldPoint: event.worldPoint,
                          paths: renderPaths(),
                          pointsPerWorldUnit: event.pointsPerWorldUnit)
    }

    /// Applies a click that landed on `hit` (a shape) or on nothing (`nil`).
    func select(_ hit: PathSelection?, extend: Bool) {
        // Picking shapes for a toolpath bypasses the normal selection entirely
        // (see D2_CanvasState.isPickingPaths); an empty click keeps the picks.
        if canvasState.isPickingPaths {
            if let hit {
                canvasState.togglePickedPath(objectID: hit.objectID, pathIndex: hit.pathIndex)
            }
            return
        }
        if let hit {
            if extend {
                canvasState.togglePathSelection(objectID: hit.objectID, pathIndex: hit.pathIndex)
            } else {
                canvasState.selectPath(objectID: hit.objectID, pathIndex: hit.pathIndex)
            }
        } else if !extend {
            // Only clear on an empty-space click when not multi-selecting,
            // so a stray shift/cmd click on empty canvas doesn't wipe the selection.
            canvasState.clearSelection()
        }
    }

    /// Drops the shape selection (not the picks of an open toolpath).
    func clearSelection() {
        guard !canvasState.isPickingPaths else {
            return
        }
        canvasState.clearSelection()
    }

    // MARK: CanvasPointerHandler

    func pointerDown(_ event: CanvasPointerEvent) -> CanvasPointerDragAction {
        lastDragWorldPoint = event.worldPoint
        isMovingSelection = false
        movingStepModelID = nil

        // The rotation-center handle of a selected object moves the selection. Checked before
        // anything else, so objects selected in the list can be dragged while a toolpath is open.
        if isSelectedObjectHandleHit(event) {
            isMovingSelection = true
            return .handled
        }
        if let handle = stepModelHandle, isHit(event, at: handle.center) {
            movingStepModelID = handle.id
            return .handled
        }
        return .camera
    }

    func pointerDragged(_ event: CanvasPointerEvent) {
        didMoveInThisEvent = false
        if isMovingSelection, let lastWorld = lastDragWorldPoint {
            canvasState.moveSelection(dx: event.worldPoint.x - lastWorld.x,
                                      dy: event.worldPoint.y - lastWorld.y)
            didMoveInThisEvent = true
            onSelectionMoved?()
        }
        if let id = movingStepModelID, let lastWorld = lastDragWorldPoint {
            onStepModelMoved?(id, event.worldPoint.x - lastWorld.x, event.worldPoint.y - lastWorld.y)
        }
        lastDragWorldPoint = event.worldPoint
    }

    func pointerUp(_ event: CanvasPointerEvent) {
        lastDragWorldPoint = nil
        isMovingSelection = false
        movingStepModelID = nil
    }

    var liveRenderObjects: [RenderObject]? {
        didMoveInThisEvent ? liveObjects?() : nil
    }

    // MARK: Handle hit testing

    /// Whether the pointer is on the handle of any selected, visible object.
    private func isSelectedObjectHandleHit(_ event: CanvasPointerEvent) -> Bool {
        canvasState.objects.contains { object in
            canvasState.selectedObjectIDs.contains(object.id)
                && object.isVisible
                && isRotationCenterHit(event, object: object)
        }
    }

    /// The handle only exists (is drawn, is grabbable) for the selected
    /// object — the caller only asks about that one. Its center is the
    /// object's center, and the reach is 10 screen points at any zoom.
    private func isRotationCenterHit(_ event: CanvasPointerEvent, object: D2_Object) -> Bool {
        isHit(event, at: object.center)
    }

    private func isHit(_ event: CanvasPointerEvent, at center: CGPoint) -> Bool {
        let distance = hypot(event.worldPoint.x - center.x, event.worldPoint.y - center.y)
        return distance <= Self.rotationCenterHitRadius / max(event.pointsPerWorldUnit, 0.000001)
    }
}
