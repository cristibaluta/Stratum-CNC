//
//  SVGObjectNode.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import Foundation
import QuartzCore

final class CAM_ObjectNode {

    let objectID: UUID

    let layer: CALayer
    private let shapeLayers: [CAShapeLayer]
    private let selectionLayer: CAShapeLayer
    private let rotationCenterLayer: CAShapeLayer

    init(object: CAM_Object, baseStrokeWidth: CGFloat) {
        self.objectID = object.id

        let objectLayer = CALayer()
        objectLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        objectLayer.masksToBounds = false

        self.layer = objectLayer

        self.shapeLayers = object.paths.map {
            Self.makeShapeLayer(for: $0, strokeWidth: baseStrokeWidth)
        }

        self.selectionLayer = Self.makeSelectionLayer(width: object.originalSize.width,
                                                      height: object.originalSize.height,
                                                      strokeWidth: baseStrokeWidth)

        self.rotationCenterLayer = CenterShapeLayer(width: object.originalSize.width,
                                                    height: object.originalSize.height,
                                                    strokeWidth: baseStrokeWidth)
        self.rotationCenterLayer.zPosition = 101

        for shapeLayer in shapeLayers {
            objectLayer.addSublayer(shapeLayer)
        }

        objectLayer.addSublayer(selectionLayer)
        objectLayer.addSublayer(rotationCenterLayer)
    }
}

// MARK: - Rendering

extension CAM_ObjectNode {

    func update(object: CAM_Object,
                zoomScale: CGFloat,
                objectSelected: Bool,
                selectedPathIndexes: [Int]) {

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layer.bounds = CGRect(origin: .zero, size: object.originalSize)
        layer.position = object.center

        var transform = CGAffineTransform.identity
        transform = transform.scaledBy(x: object.scale, y: object.scale)
        transform = transform.rotated(by: object.rotationDegrees * .pi / 180)

        layer.setAffineTransform(transform)

        updateStyles(object: object,
                     zoomScale: zoomScale,
                     objectSelected: objectSelected,
                     selectedPathIndexes: selectedPathIndexes)

        CATransaction.commit()
    }
}

// MARK: - Private Rendering

private extension CAM_ObjectNode {

    func updateStyles(object: CAM_Object,
                      zoomScale: CGFloat,
                      objectSelected: Bool,
                      selectedPathIndexes: [Int]) {

        let effectiveScale = max(zoomScale * object.scale, 0.000001)

        for (index, shapeLayer) in shapeLayers.enumerated() {

            let isPathSelected = selectedPathIndexes.contains(index)

            if objectSelected {
                shapeLayer.strokeColor = STColor.systemRed.cgColor
                shapeLayer.lineWidth = 2.5 / effectiveScale

            } else if isPathSelected {
                shapeLayer.strokeColor = STColor.systemBlue.cgColor
                shapeLayer.lineWidth = 2.0 / effectiveScale

            } else {
                shapeLayer.strokeColor = STColor.labelColor.cgColor
                shapeLayer.lineWidth = 1.0 / effectiveScale
            }
        }

        selectionLayer.opacity = objectSelected ? 1 : 0
        rotationCenterLayer.opacity = objectSelected ? 1 : 0
        selectionLayer.lineWidth = 1.0 / effectiveScale
        rotationCenterLayer.lineWidth = 1.0 / effectiveScale
    }

    static func makeShapeLayer(for path: STBezierPath, strokeWidth: CGFloat) -> CAShapeLayer {

        let layer = CAShapeLayer()

        layer.path = path.cgPath
        layer.fillColor = nil
        layer.strokeColor = STColor.labelColor.cgColor
        layer.lineWidth = strokeWidth
        layer.lineJoin = .round
        layer.lineCap = .round

        layer.actions = [
            "strokeColor": NSNull(),
            "lineWidth": NSNull()
        ]

        return layer
    }

    static func makeSelectionLayer(width: CGFloat, height: CGFloat, strokeWidth: CGFloat) -> CAShapeLayer {

        let layer = CAShapeLayer()
        let path = CGMutablePath()

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()

        layer.path = path
        layer.fillColor = nil
        layer.strokeColor = STColor.systemRed.cgColor
        layer.lineWidth = strokeWidth
        layer.lineDashPattern = [6, 4]
        layer.opacity = 0
        layer.zPosition = 100

        return layer
    }
}
