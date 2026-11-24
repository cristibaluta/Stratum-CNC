//
//  CanvasRenderMode.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//


//
//  CanvasRenderMode.swift
//  Stratum CNC
//
//  Which of the two canvas renderers is currently showing. `MetalRenderer`
//  reads this every frame to decide which draw path to take in `draw(in:)`.
//  M4: exposed as a `@Published` property on `CanvasSceneModel`
//  (`CanvasSceneModel.renderMode`), fed into `MetalRenderer.renderMode`
//  through `MetalCanvasView`, with a segmented `Picker` over `CanvasSection`
//  as the actual UI toggle — see `ControllerView.swift`.
//
enum CanvasRenderMode: CaseIterable, Hashable {
    /// The existing hidden-line wireframe view: toolpath rapid/cutting
    /// lines, the stock outline, the tool marker — everything driven by
    /// `RenderObject`/`RenderRole` through the two-pass technique in
    /// `MetalRenderer.drawWireframe`.
    case wireframe

    /// The 2.5D heightmap stock preview built from `HeightmapGrid`/
    /// `HeightmapMesh`. Axes and the tool marker still draw in this mode
    /// (see `MetalRenderer.heightmapWireframeHiddenRoles`); the stock
    /// wireframe and toolpath lines don't — the shaded surface stands in
    /// for both.
    case heightmap

    /// Label/icon for the mode-toggle `Picker` in `CanvasSection`.
    var label: String {
        switch self {
            case .wireframe: return "Wireframe"
            case .heightmap: return "Heightmap"
        }
    }

    var systemImage: String {
        switch self {
            case .wireframe: return "cube.transparent"
            case .heightmap: return "mountain.2.fill"
        }
    }
}