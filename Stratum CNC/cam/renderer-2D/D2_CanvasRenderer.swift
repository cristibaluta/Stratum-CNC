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

        stockLayer.zPosition = -2
        rulerLayer.zPosition = -1
        objectsLayer.zPosition = 0
        toolpathsLayer.zPosition = 1
    }

    func removeAll() {
        objectsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        nodes.removeAll()
    }

    func render(state canvasState: D2_CanvasState) {

        stockLayer.isHidden = !canvasState.isStockVisible
        stockLayer.zoomScale = canvasState.zoomScale
//        stockLayer.updateMaterial(with: canvasState.stock)
        rulerLayer.updateRulerStrokeWidth(zoomScale: canvasState.zoomScale)

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
                        selectedPathIndexes: selectedPathIndexes)
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
