//
//  CAMCanvasInteraction.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  The plan's "E": `D2_CanvasNSView.mouseDown/mouseDragged/mouseUp`, ported
//  almost verbatim. The state machine (`pendingPick`, `dragMode`,
//  `clickDragThreshold`) and every call into `D2_CanvasState`
//  (`selectPath`, `togglePathSelection`, `clearSelection`, `moveObject`,
//  `togglePickedPath`) are unchanged. The two substitutions:
//    - `layer?.convert(viewPoint, to: workLayer)` → `event.worldPoint`
//      (`Camera.worldPoint(atScreenNDC:)`, done by `MetalCanvasView`)
//    - `PathHitTester` against layers → against `D2_RenderPath.worldPath`
//  Panning is `MetalCanvasView`'s job now: returning `.pan` from
//  `pointerDown` is the old `dragMode = .pan`.
//
//  Behavior kept on purpose, even where it's odd:
//    - a plain drag always pans, even when it started on a shape (it only
//      *selects* it); the one exception is a drag that starts on the
//      selected object's rotation-center handle, which moves the object
//    - Shift or Cmd extends/toggles the path selection; an empty-space
//      click clears it only without those modifiers
//    - while picking shapes for a toolpath, clicks toggle picks on mouse-UP
//      and only if the cursor barely moved, so click-dragging over a shape
//      pans instead of toggling it
//

import Foundation
import CoreGraphics

@MainActor
final class CAMCanvasInteraction: CanvasPointerHandler {

    private enum DragMode {
        case pan
        case moveObject(UUID)
    }

    private static let clickDragThreshold: CGFloat = 4
    /// Screen points, like `PathHitTester.tolerance`.
    private static let rotationCenterHitRadius: CGFloat = 10

    private let canvasState: D2_CanvasState
    /// Reads the *current* per-path geometry from the scene model, so a hit
    /// is tested against exactly what was last drawn.
    private let renderPaths: () -> [D2_RenderPath]
    private let hitTester = PathHitTester(tolerance: 6)

    private var dragMode: DragMode = .pan
    private var lastDragWorldPoint: CGPoint?
    private var pendingPick: (selection: PathSelection, startLocation: CGPoint)?

    init(canvasState: D2_CanvasState, renderPaths: @escaping () -> [D2_RenderPath]) {
        self.canvasState = canvasState
        self.renderPaths = renderPaths
    }

    // MARK: CanvasPointerHandler

    func pointerDown(_ event: CanvasPointerEvent) -> CanvasPointerDragAction {

        lastDragWorldPoint = event.worldPoint
        dragMode = .pan
        pendingPick = nil

        // Picking shapes for a toolpath: bypass the normal object/path
        // selection entirely (see D2_CanvasState.isPickingPaths).
        if canvasState.isPickingPaths {
            if let hit = hitTest(event) {
                pendingPick = (selection: hit, startLocation: event.viewPoint)
            }
            return .pan
        }

        if let selectedObjectID = canvasState.selectedObjectIDs.first,
           let object = canvasState.object(withID: selectedObjectID),
           isRotationCenterHit(event, object: object) {
            canvasState.selectObject(selectedObjectID)
            dragMode = .moveObject(selectedObjectID)
            return .handled
        }

        // Shift or Cmd held -> extend/toggle the selection instead of replacing it.
        let isMultiSelectModifierDown = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)

        if let hit = hitTest(event) {
            if isMultiSelectModifierDown {
                canvasState.togglePathSelection(objectID: hit.objectID, pathIndex: hit.pathIndex)
            } else {
                canvasState.selectPath(objectID: hit.objectID, pathIndex: hit.pathIndex)
            }
        } else if !isMultiSelectModifierDown {
            // Only clear on an empty-space click when not multi-selecting,
            // so a stray shift/cmd click on empty canvas doesn't wipe the selection.
            canvasState.clearSelection()
        }
        return .pan
    }

    func pointerDragged(_ event: CanvasPointerEvent) {

        // Moved too far to be a click: it's a pan, not a pick.
        if let pick = pendingPick,
           hypot(event.viewPoint.x - pick.startLocation.x,
                 event.viewPoint.y - pick.startLocation.y) > Self.clickDragThreshold {
            pendingPick = nil
        }

        if case .moveObject(let objectID) = dragMode,
           let lastWorld = lastDragWorldPoint,
           let object = canvasState.object(withID: objectID) {

            let newPosition = CGPoint(x: object.position.x + (event.worldPoint.x - lastWorld.x),
                                      y: object.position.y + (event.worldPoint.y - lastWorld.y))
            canvasState.moveObject(objectID, to: newPosition)
        }

        lastDragWorldPoint = event.worldPoint
    }

    func pointerUp(_ event: CanvasPointerEvent) {
        if let pick = pendingPick {
            canvasState.togglePickedPath(objectID: pick.selection.objectID,
                                         pathIndex: pick.selection.pathIndex)
            pendingPick = nil
        }
        lastDragWorldPoint = nil
        dragMode = .pan
    }

    // MARK: Hit testing

    private func hitTest(_ event: CanvasPointerEvent) -> PathSelection? {
        hitTester.hitTest(worldPoint: event.worldPoint,
                          paths: renderPaths(),
                          pointsPerWorldUnit: event.pointsPerWorldUnit)
    }

    /// The handle only exists (is drawn, is grabbable) for the selected
    /// object — the caller only asks about that one. Its center is the
    /// object's center, and the reach is 10 screen points at any zoom.
    private func isRotationCenterHit(_ event: CanvasPointerEvent, object: D2_Object) -> Bool {
        let center = object.center
        let distance = hypot(event.worldPoint.x - center.x, event.worldPoint.y - center.y)
        return distance <= Self.rotationCenterHitRadius / max(event.pointsPerWorldUnit, 0.000001)
    }
}
