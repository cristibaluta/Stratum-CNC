//
//  CanvasLayer.swift
//  Stratum CNC
//
//  The things a canvas draws, as the person sees them in the objects list
//  over the canvas (`CanvasLayersList`) — each one a checkmark that shows or
//  hides it. A layer is one or more `RenderRole`s; the model keeps drawing
//  everything and only the list handed to the renderer is filtered.
//
//  Each canvas lists only the layers it has: the controller's are
//  `controllerLayers`; the CAM canvas lists the ones it has content for
//  (see `CAMLayersOverlay`).
//

import SwiftUI

enum CanvasLayer: String, CaseIterable, Identifiable {
    case model
    case stock
    case rapidMoves
    case cuttingMoves
    case tool
    case workbed
    /// The L-bracket together with its graduated ruler
    case anchor
    case boundingBox
    case axes
    /// Not a render object: the coordinate pills drawn over the canvas
    case coordinates
    /// CAM canvas: the flat shapes (SVG, DXF, Gerber) with their selection overlays
    case shapes
    /// CAM canvas: the generated toolpath previews of every face, the rest areas and the holding tabs
    case toolpaths

    var id: String { rawValue }

    /// What the controller's canvas lists, in the order it lists them.
    static let controllerLayers: [CanvasLayer] = [
        .model, .stock, .rapidMoves, .cuttingMoves, .tool,
        .workbed, .anchor, .boundingBox, .axes, .coordinates
    ]

    var label: String {
        switch self {
            case .model:        return "Model"
            case .stock:        return "Stock"
            case .rapidMoves:   return "Rapid moves"
            case .cuttingMoves: return "Cutting moves"
            case .tool:         return "Tool"
            case .workbed:      return "Work bed"
            case .anchor:       return "Anchor"
            case .boundingBox:  return "Job area"
            case .axes:         return "Axes"
            case .coordinates:  return "Coordinates"
            case .shapes:       return "Shapes"
            case .toolpaths:    return "Toolpaths"
        }
    }

    /// Tooltip of the gear next to the layer, for the layers that have settings.
    var settingsHelp: String {
        "\(label) settings"
    }

    /// The render roles this layer switches. A macro preview's moves follow
    /// the matching program moves, so one checkbox covers both.
    var roles: Set<RenderRole> {
        switch self {
            case .model:        return [.model, .modelSelection]
            case .stock:        return [.stock]
            case .rapidMoves:   return [.toolpathRapid, .macroRapid]
            case .cuttingMoves: return [.toolpathCutting, .macroCutting]
            case .tool:         return [.tool]
            case .workbed:      return [.workbed]
            // CAM draws the ruler as an object of its own (`.ruler`); in the controller it is part of `.anchor`
            case .anchor:       return [.anchor, .ruler]
            case .boundingBox:  return [.boundingBox]
            case .axes:         return [.axes]
            // Not told apart by role: the CAM scene leaves them out of what it builds
            case .coordinates, .shapes, .toolpaths: return []
        }
    }

    /// The color the canvas draws this in, for tinting its checkbox. `nil`
    /// where there isn't one color (the axes are red/green/blue; the
    /// coordinate pills take their colors from the bed and the anchor).
    var color: SIMD4<Float>? {
        switch self {
            case .model:        return CanvasPalette.model
            case .stock:        return CanvasPalette.stock
            case .rapidMoves:   return CanvasPalette.rapid
            case .cuttingMoves: return CanvasPalette.cutting
            case .tool:         return CanvasPalette.tool
            case .workbed:      return CanvasPalette.workbed
            case .anchor:       return CanvasPalette.anchor
            case .boundingBox:  return CanvasPalette.boundingBox
            // Shapes and toolpaths are drawn in several colors (selection, one per face)
            case .axes, .coordinates, .shapes, .toolpaths: return nil
        }
    }

    var tint: Color? {
        color.map { Color(canvasColor: $0) }
    }

    /// Heightmap mode shows the carved surface instead of the toolpath
    /// lines (see `MetalRenderer.heightmapWireframeHiddenRoles`), so these
    /// two have nothing to switch there.
    var isWireframeOnly: Bool {
        self == .rapidMoves || self == .cuttingMoves
    }
}

extension Color {
    /// A color of the canvas's palette (`SIMD4<Float>` RGBA) as a SwiftUI color.
    init(canvasColor c: SIMD4<Float>) {
        self.init(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
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

    /// Why the layer can't be switched right now, or `nil` when it can.
    func unavailableReason(for layer: CanvasLayer) -> String? {
        if layer.isWireframeOnly && renderMode == .heightmap {
            return "Not drawn in heightmap mode"
        }
        return hasContent(layer) ? nil : "Nothing to show yet"
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

    /// The heightmap surface is the stock in heightmap mode, so the Stock checkbox hides it too.
    var visibleHeightmapMesh: HeightmapMesh? {
        hiddenLayers.contains(.stock) ? nil : heightmapMesh
    }
}
