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
    let stockLayer = CALayer()
    let stockFillLayer = CAShapeLayer()
    let stockTextureLayer = CAShapeLayer()
    let stockTextureMaskLayer = CAShapeLayer()
    let rulerLayer: RulerShapeLayer
    let objectsLayer = CALayer()
    let testLayer = CAShapeLayer()

    private(set) var nodes: [UUID: D2_ObjectNode] = [:]
    private let baseStrokeWidth: CGFloat = 1.0
    private let rulerLength: CGFloat = 200

    init() {
        rulerLayer = RulerShapeLayer(rulerLength: rulerLength)
        configureLayers()
    }

    func setObjects(_ objects: [D2_Object]) {
        removeAll()
        let nodes = objects.map { D2_ObjectNode(object: $0, baseStrokeWidth: baseStrokeWidth) }
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
    func render(objects: [D2_Object],
                stock: StockMaterial,
                isStockVisible: Bool,
                zoomScale: CGFloat,
                selectedObjectIDs: Set<UUID>,
                selectedPaths: [PathSelection]) {

        stockLayer.isHidden = !isStockVisible
        updateStockLayer(with: stock)

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
        stockFillLayer.lineWidth = 1 / zoomScale
        stockTextureLayer.lineWidth = 0.4 / zoomScale
    }

    private func updateStockLayer(with stock: StockMaterial) {
        let stockPath = CGMutablePath()
        var stockBounds = CGRect.zero

        switch stock.geometry {
        case .rectangular(let width, let height, _):
            stockBounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
            stockPath.addRect(stockBounds)

        case .cylindrical(let diameter, _):
            let size = CGFloat(diameter)
            stockBounds = CGRect(x: 0, y: 0, width: size, height: size)
            stockPath.addEllipse(in: stockBounds)

        case .disk(let outerDiameter, let innerDiameter, _):
            let outerSize = CGFloat(outerDiameter)
            let innerRadius = CGFloat(innerDiameter) / 2
            stockBounds = CGRect(x: 0, y: 0, width: outerSize, height: outerSize)

            stockPath.addEllipse(in: stockBounds)
            let outerCenter = CGPoint(x: stockBounds.midX, y: stockBounds.midY)
            stockPath.addEllipse(in: CGRect(
                x: outerCenter.x - innerRadius,
                y: outerCenter.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            ))
        }

        stockFillLayer.path = stockPath
        stockTextureLayer.path = hatchTexturePath(in: stockBounds, spacing: 5)
        stockTextureMaskLayer.path = stockPath

        if case .disk = stock.geometry {
            stockFillLayer.fillRule = .evenOdd
            stockTextureMaskLayer.fillRule = .evenOdd
        } else {
            stockFillLayer.fillRule = .nonZero
            stockTextureMaskLayer.fillRule = .nonZero
        }

        applyStockStyle(material: stock.material)
    }

    private func applyStockStyle(material: StockMaterialType) {
        let fillColor: NSColor

        switch material {
            case .aluminum, .steel, .stainless_steel:
                fillColor = NSColor.systemGray.withAlphaComponent(0.08)
            case .copper, .brass, .bronze, .pcb, .bicolor_stock:
                fillColor = NSColor(srgbRed: 0.72, green: 0.45, blue: 0.20, alpha: 1.0).withAlphaComponent(0.12)
            case .wood, .hardwood, .softwood, .plywood:
                fillColor = NSColor.systemBrown.withAlphaComponent(0.08)
            case .plastic, .acrylic, .hdpe, .pvc, .delrin, .epoxy, .bakelite, .synthetic_stone, .polycarbonate:
                fillColor = NSColor.systemTeal.withAlphaComponent(0.07)
            case .carbon_fiber:
                fillColor = NSColor.systemGray.withAlphaComponent(0.40)
            case .custom:
                fillColor = NSColor.systemBlue.withAlphaComponent(0.07)
        }

        stockFillLayer.fillColor = fillColor.cgColor
        stockFillLayer.strokeColor = fillColor.withAlphaComponent(0.35).cgColor

        // A very light hatch so the material remains visible without competing with toolpaths.
        stockTextureLayer.fillColor = nil
        stockTextureLayer.strokeColor = fillColor.withAlphaComponent(0.10).cgColor
        stockTextureLayer.lineDashPattern = [2, 6]
    }

    private func hatchTexturePath(in bounds: CGRect, spacing: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard bounds.width > 0, bounds.height > 0 else {
            return path
        }

        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY
        let start = minX - bounds.height

        var x = start
        while x <= maxX {
            path.move(to: CGPoint(x: x, y: minY))
            path.addLine(to: CGPoint(x: x + bounds.height, y: maxY))
            x += spacing
        }

        return path
    }

    private func configureLayers() {
        workLayer.anchorPoint = .zero
        workLayer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        stockLayer.addSublayer(stockFillLayer)
        stockLayer.addSublayer(stockTextureLayer)
        stockTextureLayer.mask = stockTextureMaskLayer
        workLayer.addSublayer(stockLayer)
        workLayer.addSublayer(rulerLayer)
        workLayer.addSublayer(objectsLayer)
        workLayer.addSublayer(testLayer)

        stockLayer.zPosition = -3
        rulerLayer.zPosition = -2
        objectsLayer.zPosition = 0
        testLayer.zPosition = -1

        stockFillLayer.actions = ["path": NSNull(), "lineWidth": NSNull()]
        stockTextureLayer.actions = ["path": NSNull(), "lineWidth": NSNull()]
        stockTextureMaskLayer.actions = ["path": NSNull()]
    }
}
