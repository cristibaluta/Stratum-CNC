//
//  CanvasPointerHandler.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  How a `MetalCanvasView` reports the mouse to its owner (CAM). The view
//  knows about cameras and pixels; the owner knows about shapes. This is the
//  seam between them, so `MetalCanvasView` never imports anything CAM-specific.
//

import AppKit
import simd

/// One mouse event, already translated out of screen space.
struct CanvasPointerEvent {
    /// Where the cursor is on the shapes' plane (z = 0), in the shapes' own coordinates (mm):
    /// the camera ray through the cursor, intersected with z = 0 and taken back through the
    /// flat overlay's transform. Under an orbited camera that is still the point on the
    /// drawing the cursor is over.
    let worldPoint: CGPoint
    /// The cursor in the view's own coordinates (points, origin bottom-left)
    /// — for "did it move far enough to be a drag" checks, which are about
    /// screen distance and must not change with zoom.
    let viewPoint: CGPoint
    let modifierFlags: NSEvent.ModifierFlags
    /// Current zoom: how many view points one world mm covers (across the view direction).
    /// Divide a screen-space tolerance by this to get a world-space one.
    let pointsPerWorldUnit: CGFloat
}

/// A press-and-release that did not move: everything the owner needs to resolve what was clicked,
/// whether that is a flat shape (`pointer`) or an edge of a 3D model (`viewPoint`, `viewSize`, `matrix`).
struct CanvasClick {
    /// `nil` when the camera is edge-on to the z = 0 plane, where no point on it can be told.
    let pointer: CanvasPointerEvent?
    let viewPoint: CGPoint
    let viewSize: CGSize
    /// The exact matrix the part is rendered with (camera and part transform).
    let matrix: simd_float4x4
    let modifierFlags: NSEvent.ModifierFlags

    /// Shift or Cmd extends / toggles the selection instead of replacing it.
    var extendsSelection: Bool {
        modifierFlags.contains(.shift) || modifierFlags.contains(.command)
    }
}

/// What the rest of a press-drag-release should do.
enum CanvasPointerDragAction {
    /// The drag moves the camera (orbit, pan or zoom, per `CanvasInputSettings`).
    case camera
    /// The handler is using the drag itself (e.g. moving an object); the
    /// camera stays put.
    case handled
}

@MainActor
protocol CanvasPointerHandler: AnyObject {
    /// Decides what this press starts. Always followed by `pointerDragged`
    /// events and finally `pointerUp`.
    func pointerDown(_ event: CanvasPointerEvent) -> CanvasPointerDragAction
    func pointerDragged(_ event: CanvasPointerEvent)
    func pointerUp(_ event: CanvasPointerEvent)

    /// Geometry the handler has just changed in response to `pointerDragged`. When non-nil
    /// the view uploads it before drawing, so a drag shows up in the very same frame
    /// instead of waiting for SwiftUI to push the rebuilt scene.
    var liveRenderObjects: [RenderObject]? { get }
}

extension CanvasPointerHandler {
    var liveRenderObjects: [RenderObject]? { nil }
}
