//
//  CanvasPointerHandler.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  How a `.locked2D` `MetalCanvasView` reports the mouse to its owner: the
//  Metal-side replacement for `D2_CanvasNSView.mouseDown/mouseDragged/mouseUp`.
//  The view knows about cameras and pixels; the owner (CAM) knows about
//  shapes. This is the seam between them, so `MetalCanvasView` never
//  imports anything CAM-specific.
//

import AppKit

/// One mouse event, already translated out of screen space.
struct CanvasPointerEvent {
    /// Where the cursor is on the z = 0 plane, in world coordinates (mm).
    /// Replaces the old `layer?.convert(viewPoint, to: workLayer)`.
    let worldPoint: CGPoint
    /// The cursor in the view's own coordinates (points, origin bottom-left)
    /// — for "did it move far enough to be a drag" checks, which are about
    /// screen distance and must not change with zoom.
    let viewPoint: CGPoint
    let modifierFlags: NSEvent.ModifierFlags
    /// Current zoom: how many view points one world mm covers. What the old
    /// code called `zoomScale`. Divide a screen-space tolerance by this to
    /// get a world-space one.
    let pointsPerWorldUnit: CGFloat
}

/// What the rest of a press-drag-release should do to the camera.
enum CanvasPointerDragAction {
    /// The canvas pans with the drag (the old `DragMode.pan`).
    case pan
    /// The handler is using the drag itself (e.g. moving an object); the
    /// camera stays put.
    case handled
}

@MainActor
protocol CanvasPointerHandler: AnyObject {
    /// Decides what this press starts. Always followed by `pointerDragged`
    /// events (even when it returned `.pan` — the handler may need them, e.g.
    /// to cancel a pending click) and finally `pointerUp`.
    func pointerDown(_ event: CanvasPointerEvent) -> CanvasPointerDragAction
    func pointerDragged(_ event: CanvasPointerEvent)
    func pointerUp(_ event: CanvasPointerEvent)
}
