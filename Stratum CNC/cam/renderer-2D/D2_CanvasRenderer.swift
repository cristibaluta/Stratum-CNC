//
//  NumberTextField.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit
import QuartzCore

final class D2_CanvasRenderer {
    
    let workLayer = CALayer()
    let rulerLayer: RulerShapeLayer
    let objectsLayer = CALayer()
    let testLayer = CAShapeLayer()

    private(set) var nodes: [UUID: CAM_ObjectNode] = [:]
    private let baseStrokeWidth: CGFloat = 1.0
    private let rulerLength: CGFloat = 200

    init() {
        rulerLayer = RulerShapeLayer(rulerLength: rulerLength)
        configureLayers()
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
        rulerLayer.updateRulerStrokeWidth(zoomScale: zoomScale)
    }

    private func configureLayers() {
        workLayer.anchorPoint = .zero
        workLayer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        workLayer.addSublayer(rulerLayer)
        workLayer.addSublayer(objectsLayer)
        workLayer.addSublayer(testLayer)
    }
}
