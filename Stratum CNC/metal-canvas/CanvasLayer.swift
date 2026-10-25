//
//  CanvasLayer.swift
//  Stratum CNC
//
//  The things the controller's canvas draws, as the person sees them in the
//  objects list over the canvas — each one a checkmark that shows or hides
//  it. A layer is one or more `RenderRole`s; the model keeps drawing
//  everything and only the list handed to the renderer is filtered.
//

import SwiftUI

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
    /// Not a render object: the coordinate pills drawn over the canvas
    /// (`CanvasCoordinateLabels`). One entry hides them all.
    case coordinates

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
            case .coordinates:  return "Coordinates"
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
            case .coordinates:  return []
        }
    }

    /// The color the canvas draws this in, for tinting its checkbox. `nil`
    /// where there isn't one color (the axes are red/green/blue; the
    /// coordinate pills take their colors from the bed and the anchor).
    var color: SIMD4<Float>? {
        switch self {
            case .stock:        return CanvasPalette.stock
            case .rapidMoves:   return CanvasPalette.rapid
            case .cuttingMoves: return CanvasPalette.cutting
            case .boundingBox:  return CanvasPalette.boundingBox
            case .tool:         return CanvasPalette.tool
            case .workbed:      return CanvasPalette.workbed
            case .anchor:       return CanvasPalette.anchor
            case .ruler:        return CanvasPalette.ruler
            case .axes, .coordinates: return nil
        }
    }

    var tint: Color? {
        color.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }
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
        if layer == .coordinates {
            return true
        }
        return renderObjects.contains { object in
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
