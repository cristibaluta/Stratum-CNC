//
//  RulerShapeLayer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import AppKit
import QuartzCore

class RulerShapeLayer: CAShapeLayer {

    private let rulerLength: CGFloat
    private let baseStrokeWidth: CGFloat = 1.0

    init(rulerLength: CGFloat) {
        self.rulerLength = rulerLength
        super.init()
        buildRuler()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildRuler() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rulerLength, y: 0))
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rulerLength))

        addTicks(to: path, alongX: true)
        addTicks(to: path, alongX: false)

        self.path = path
        self.strokeColor = STColor.secondaryLabelColor.cgColor
        self.fillColor = nil
        self.lineWidth = baseStrokeWidth
        self.zPosition = -1
        self.actions = ["lineWidth": NSNull()]
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

    func updateRulerStrokeWidth(zoomScale: CGFloat) {
        self.lineWidth = baseStrokeWidth / max(zoomScale, 0.000001)
    }
}
