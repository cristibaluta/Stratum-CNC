//
//  D2_CanvasRenderer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit
import QuartzCore

final class D2_CanvasRenderer {

    let workLayer = CALayer()
    let stockLayer = StockLayer()
    let rulerLayer: RulerShapeLayer
    let objectsLayer = CALayer()
    let toolpathsLayer = CAShapeLayer()

    private(set) var nodes: [UUID: D2_ObjectNode] = [:]
    private let baseStrokeWidth: CGFloat = 1.0
    private let rulerLength: CGFloat = 200

    /// On-screen thickness of the toolpath line, in points (kept constant across zoom levels).
    private let toolpathLineWidth: CGFloat = 0.75
    /// The path currently on `toolpathsLayer`, so it's only re-assigned when it actually changed.
    private var renderedToolpathsPath: CGPath?
    /// Line width currently on `toolpathsLayer` (0 = not set yet).
    private var appliedToolpathLineWidth: CGFloat = 0

    /// The objects `nodes` were built from. Nodes only depend on an object's
    /// immutable geometry (`paths`, `originalSize`), so as long as this is the
    /// same list of the same instances, nodes are reused and merely updated.
    private var renderedObjects: [D2_Object] = []

    init() {
        rulerLayer = RulerShapeLayer(rulerLength: rulerLength)
        configureLayers()
    }

    private func configureLayers() {
        workLayer.anchorPoint = .zero
        workLayer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        
        workLayer.addSublayer(stockLayer)
        workLayer.addSublayer(rulerLayer)
        workLayer.addSublayer(objectsLayer)
        workLayer.addSublayer(toolpathsLayer)

        toolpathsLayer.fillColor = nil
        toolpathsLayer.strokeColor = STColor.systemBlue.cgColor
        toolpathsLayer.lineJoin = .round
        toolpathsLayer.lineCap = .round

        stockLayer.zPosition = -2
        rulerLayer.zPosition = -1
        objectsLayer.zPosition = 0
        toolpathsLayer.zPosition = 1
    }

    private func renderToolpaths(state canvasState: D2_CanvasState) {

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Re-assigning a large path makes Core Animation re-tessellate it, so only do it on change.
        if renderedToolpathsPath !== canvasState.toolpathsPath {
            toolpathsLayer.path = canvasState.toolpathsPath
            renderedToolpathsPath = canvasState.toolpathsPath
        }

        // Changing lineWidth makes Core Animation re-stroke the whole (large) path,
        // so during a zoom only do it once the width is visibly off (>15%) —
        // for a hairline that's imperceptible, and it turns hundreds of
        // restrokes per pinch into a handful.
        let desiredWidth = toolpathLineWidth / max(canvasState.zoomScale, 0.000001)
        if appliedToolpathLineWidth == 0 || abs(desiredWidth - appliedToolpathLineWidth) > appliedToolpathLineWidth * 0.15 {
            toolpathsLayer.lineWidth = desiredWidth
            appliedToolpathLineWidth = desiredWidth
        }

        CATransaction.commit()
    }

    /// Rebuilds the layer tree only when the set of objects actually changed
    /// (added, removed, replaced, reordered). Moves, rotations, scaling,
    /// selection and zoom don't — `D2_ObjectNode.update` handles those on the
    /// existing layers. Previously every render recreated every CAShapeLayer.
    private func syncNodes(with objects: [D2_Object]) {

        let unchanged = objects.count == renderedObjects.count
            && zip(objects, renderedObjects).allSatisfy { $0 === $1 }
        guard !unchanged else {
            return
        }

        removeAll()
        for obj in objects {
            let node = D2_ObjectNode(object: obj, baseStrokeWidth: baseStrokeWidth)
            nodes[obj.id] = node
            objectsLayer.addSublayer(node.layer)
        }
        renderedObjects = objects
    }

    func removeAll() {
        objectsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        nodes.removeAll()
        renderedObjects = []
    }

    func render(state canvasState: D2_CanvasState) {

        stockLayer.isHidden = !canvasState.isStockVisible
        stockLayer.zoomScale = canvasState.zoomScale
        if let stock = canvasState.stock {
            stockLayer.updateMaterial(with: stock)
        }
        rulerLayer.updateRulerStrokeWidth(zoomScale: canvasState.zoomScale)

        renderToolpaths(state: canvasState)

        syncNodes(with: canvasState.objects)

        for obj in canvasState.objects {
            guard let node = nodes[obj.id] else {
                continue
            }

            let selected = canvasState.selectedObjectIDs.contains(obj.id)
            let selectedPathIndexes: [Int] = canvasState.selectedPaths.compactMap {
                ($0.objectID == obj.id) ? $0.pathIndex : nil
            }

            node.update(object: obj,
                        zoomScale: canvasState.zoomScale,
                        objectSelected: selected,
                        selectedPathIndexes: selectedPathIndexes,
                        pickedPathIndexes: canvasState.pickedPathIndices(for: obj))
        }
    }
}

// For testing purposes render the flattened version
//            let flattenedPoints = BezierPathFlattener.flatten(object.paths, tolerance: 0.02)
//            let path = CGMutablePath()
//            for points in flattenedPoints {
////                print("Subpath: \(points)")
//                path.move(to: points.first!)
//                for point in points {
//                    path.addLine(to: point)
//                }
//            }
//            testLayer.path = path
//            testLayer.strokeColor = NSColor.blue.cgColor
//            testLayer.fillColor = nil
//            testLayer.lineWidth = 0.5
//            testLayer.zPosition = -1
//            testLayer.actions = ["lineWidth": NSNull()]
