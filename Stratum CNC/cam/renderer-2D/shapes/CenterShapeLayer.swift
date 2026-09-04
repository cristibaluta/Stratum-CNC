//
//  CenterShapeLayer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import AppKit
import QuartzCore

class CenterShapeLayer: CAShapeLayer {

    init(width: CGFloat, height: CGFloat, strokeWidth: CGFloat) {
        super.init()
        makeLayer(width: width, height: height, strokeWidth: strokeWidth)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeLayer(width: CGFloat, height: CGFloat, strokeWidth: CGFloat) {

        let center = CGPoint(x: width / 2, y: height / 2)
        let radius: CGFloat = 3.5
        let crossSize: CGFloat = 7

        let path = CGMutablePath()

        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        path.move(to: CGPoint(x: center.x - crossSize, y: center.y))
        path.addLine(to: CGPoint(x: center.x + crossSize, y: center.y))

        path.move(to: CGPoint(x: center.x, y: center.y - crossSize))
        path.addLine(to: CGPoint(x: center.x, y: center.y + crossSize))

        self.path = path
        self.fillColor = NSColor.systemOrange.cgColor
        self.strokeColor = NSColor.systemOrange.cgColor
        self.shadowOffset = .zero
        self.shadowColor = NSColor.black.cgColor
        self.shadowOpacity = 0.5
        self.lineWidth = strokeWidth
        self.opacity = 0
    }
}
