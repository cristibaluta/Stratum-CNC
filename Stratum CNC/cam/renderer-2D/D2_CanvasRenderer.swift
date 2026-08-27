//
//  NumberTextField.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit
import QuartzCore

final class D2_CanvasRenderer {
    
    let worldLayer = CALayer()
    let rulerLayer = CAShapeLayer()
    let objectsLayer = CALayer()
    let testLayer = CAShapeLayer()
    private(set) var nodes: [UUID: CAM_ObjectNode] = [:]
    private let baseStrokeWidth: CGFloat = 1.0
    private let rulerLength: CGFloat = 200

    init() {
        configureLayers()
        buildRuler()
    }

    func setObjects(_ objects: [CAM_Object]) {
        removeAll()
        let nodes = objects.map { CAM_ObjectNode(object: $0, baseStrokeWidth: baseStrokeWidth) }
        for node in nodes {
            self.nodes[node.objectID] = node
            self.objectsLayer.addSublayer(node.layer)
        }
    }

    func removeAll() {
        objectsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        nodes.removeAll()
    }

    // MARK: Rendering
    func render(objects: [CAM_Object],
                zoomScale: CGFloat,
                selectedObjectIDs: Set<UUID>,
                selectedPaths: [PathSelection]) {

        for object in objects {
            guard let node = nodes[object.id] else {
                continue
            }
            let selected = selectedObjectIDs.contains(object.id)
            let selectedPathIndexes: [Int] = selectedPaths.compactMap {
                ($0.objectID == object.id) ? $0.pathIndex : nil
            }

            node.update(object: object,
                        zoomScale: zoomScale,
                        objectSelected: selected,
                        selectedPathIndexes: selectedPathIndexes)

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
        }
        updateRulerStrokeWidth(zoomScale: zoomScale)

    }

    // MARK: Setup
    private func configureLayers() {
        worldLayer.anchorPoint = .zero
        worldLayer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        worldLayer.addSublayer(rulerLayer)
        worldLayer.addSublayer(objectsLayer)
        worldLayer.addSublayer(testLayer)
    }

    // MARK: Ruler
    private func buildRuler() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rulerLength, y: 0))
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rulerLength))

        addTicks(to: path, alongX: true)
        addTicks(to: path, alongX: false)

        rulerLayer.path = path
        rulerLayer.strokeColor = NSColor.secondaryLabelColor.cgColor
        rulerLayer.fillColor = nil
        rulerLayer.lineWidth = baseStrokeWidth
        rulerLayer.zPosition = -1
        rulerLayer.actions = ["lineWidth": NSNull()]
    }

    private func addTicks(to path: CGMutablePath, alongX: Bool) {
        let millimeters = Int(rulerLength)
        for value in 0...millimeters {
            let tickLength: CGFloat = value % 10 == 0 ? 4 : value % 5 == 0 ? 2.5 : 1
            if alongX {
                let x = CGFloat(value)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: -tickLength))
            } else {
                let y = CGFloat(value)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: -tickLength, y: y))
            }
        }
    }

    private func updateRulerStrokeWidth(zoomScale: CGFloat) {
        rulerLayer.lineWidth = baseStrokeWidth / max(zoomScale, 0.000001)
    }
}
