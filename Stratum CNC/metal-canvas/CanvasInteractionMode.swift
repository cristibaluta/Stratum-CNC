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
    /// locked to `StandardView.top` and never orbits, the orientation cube
    /// is hidden (there's only one face to be oriented to), and every drag
    /// or scroll pans regardless of which button or modifier produced it —
    /// pinch still zooms, same as `.free3D`. This bypasses
    /// `CanvasInputSettings` entirely: that panel's reassignable mapping
    /// exists for a free-orbiting 3D view, and doesn't apply to a locked
    /// top-down one.
    case locked2D
}