//
//  CanvasLayer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.10.2026.
//
//  The things the controller's canvas draws, as the person sees them in the
//  objects list over the canvas — each one a checkmark that shows or hides
//  it. A layer is one or more `RenderRole`s; the model keeps drawing
//  everything and only the list handed to the renderer is filtered.
//

import Foundation

enum CanvasLayer: String, CaseIterable, Identifiable {
    case stock
    case rapidMoves
    case cuttingMoves
    case boundingBox
    case tool
    case workbed
    case anchor
    case ruler
    case axes

    var id: String { rawValue }

    var label: String {
        switch self {
            case .stock:        return "Stock"
            case .rapidMoves:   return "Rapid moves"
            case .cuttingMoves: return "Cutting moves"
            case .boundingBox:  return "Bounding box"
            case .tool:         return "Tool"
            case .workbed:      return "Work bed"
            case .anchor:       return "Anchor"
            case .ruler:        return "Ruler"
            case .axes:         return "Axes"
        }
    }

    /// The render roles this layer switches. A macro preview's moves follow
    /// the matching program moves, so one checkbox covers both.
    var roles: Set<RenderRole> {
        switch self {
            case .stock:        return [.stock]
            case .rapidMoves:   return [.toolpathRapid, .macroRapid]
            case .cuttingMoves: return [.toolpathCutting, .macroCutting]
            case .boundingBox:  return [.boundingBox]
            case .tool:         return [.tool]
            case .workbed:      return [.workbed]
            case .anchor:       return [.anchor]
            case .ruler:        return [.ruler]
            case .axes:         return [.axes]
        }
    }

    /// Heightmap mode shows the carved surface instead of the toolpath
    /// lines (see `MetalRenderer.heightmapWireframeHiddenRoles`), so these
    /// two have nothing to switch there.
    var isWireframeOnly: Bool {
        self == .rapidMoves || self == .cuttingMoves
    }
}

extension CanvasSceneModel {

    func isVisible(_ layer: CanvasLayer) -> Bool {
        !hiddenLayers.contains(layer)
    }

    func setVisible(_ layer: CanvasLayer, _ visible: Bool) {
        if visible {
            hiddenLayers.remove(layer)
        } else {
            hiddenLayers.insert(layer)
        }
    }

    /// Whether the scene has anything of this layer to draw right now — a
    /// tool before the machine has reported a position, or a bounding box
    /// before a program is loaded, has not.
    func hasContent(_ layer: CanvasLayer) -> Bool {
        renderObjects.contains { object in
            guard let role = object.role, layer.roles.contains(role) else {
                return false
            }
            return !object.points.isEmpty || !object.solidTriangles.isEmpty
        }
    }

    /// `renderObjects` without the layers the person switched off — what
    /// `MetalCanvasView` gets. Objects keep their ids, so the renderer
    /// reuses the GPU buffers of everything that stays.
    var visibleRenderObjects: [RenderObject] {
        guard !hiddenLayers.isEmpty else {
            return renderObjects
        }
        return renderObjects.filter { object in
            guard let role = object.role else {
                return true
            }
            return !hiddenLayers.contains { $0.roles.contains(role) }
        }
    }

    /// The heightmap surface is the stock in heightmap mode, so the Stock
    /// checkbox hides it too.
    var visibleHeightmapMesh: HeightmapMesh? {
        hiddenLayers.contains(.stock) ? nil : heightmapMesh
    }
}
