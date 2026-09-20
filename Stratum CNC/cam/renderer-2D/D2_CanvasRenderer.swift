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
        toolpathsLayer.lineWidth = toolpathLineWidth / max(canvasState.zoomScale, 0.000001)

        CATransaction.commit()
    }

    func removeAll() {
        objectsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        nodes.removeAll()
    }

    func render(state canvasState: D2_CanvasState) {

        stockLayer.isHidden = !canvasState.isStockVisible
        stockLayer.zoomScale = canvasState.zoomScale
        if let stock = canvasState.stock {
            stockLayer.updateMaterial(with: stock)
        }
        rulerLayer.updateRulerStrokeWidth(zoomScale: canvasState.zoomScale)

        renderToolpaths(state: canvasState)

        removeAll()
        for obj in canvasState.objects {
            let node = D2_ObjectNode(object: obj, baseStrokeWidth: baseStrokeWidth)
            self.nodes[obj.id] = node
            self.objectsLayer.addSublayer(node.layer)

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
