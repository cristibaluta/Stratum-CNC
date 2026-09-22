//
//  CanvasInteractionMode.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//


//
//  CanvasInteractionMode.swift
//  Stratum CNC
//

/// Which input scheme `MetalCanvasView` drives its camera with. Orthogonal
/// to `CanvasRenderMode` (which draw path the renderer takes) — this is
/// about what the mouse/trackpad/scroll wheel *do*, not what gets drawn.
enum CanvasInteractionMode {

    /// The controller's toolpath/heightmap preview: full orbit, pan, zoom,
    /// snap-to-face and the orientation cube, all mapped through
    /// `CanvasInputSettings.shared` exactly as today — reassignable by the
    /// user in `CanvasControlsSettingsView`.
    case free3D

    /// A 2D vector view (CAM's shapes-and-toolpaths canvas): the camera is
    /// locked to `StandardView.top` and never orbits, and the orientation
    /// cube is hidden (there's only one face to be oriented to). Every other
    /// input is mapped through `CanvasInputSettings.shared` exactly like
    /// `.free3D` — reassigning Scroll, Drag, etc. in
    /// `CanvasControlsSettingsView` affects both canvases the same way — but
    /// `Orbit` and `Snap to Face` are the two actions that would tilt the
    /// view off `.top`, so `MetalCanvasView.Coordinator` treats them as a
    /// no-op here rather than breaking the "always top-down" guarantee CAM's
    /// hit-testing and selection overlay rely on. Pinch still zooms, same as
    /// `.free3D`.
    case locked2D
}