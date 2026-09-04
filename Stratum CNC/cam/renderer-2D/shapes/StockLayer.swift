//
//  StockShapeLayer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 03/09/2026.
//

import Foundation
import QuartzCore

class StockLayer: CALayer {

    private let stockFillLayer = CAShapeLayer()
    private let stockTextureLayer = CAShapeLayer()
    private let stockTextureMaskLayer = CAShapeLayer()

    var zoomScale: CGFloat = 1.0 {
        didSet {
            stockFillLayer.lineWidth = 1 / zoomScale
            stockTextureLayer.lineWidth = 0.4 / zoomScale
        }
    }

    override init() {
        super.init()
        self.addSublayer(stockFillLayer)
        self.addSublayer(stockTextureLayer)

        stockTextureLayer.mask = stockTextureMaskLayer

        configure()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configure() {
        stockFillLayer.actions = ["path": NSNull(), "lineWidth": NSNull()]
        stockTextureLayer.actions = ["path": NSNull(), "lineWidth": NSNull()]
        stockTextureMaskLayer.actions = ["path": NSNull()]
        zoomScale = 1.0
    }

    func updateMaterial(with stock: StockMaterial) {
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
        let fillColor: STColor

        switch material {
        case .aluminum, .steel, .stainless_steel:
            fillColor = STColor.systemGray.withAlphaComponent(0.08)
        case .copper, .brass, .bronze, .pcb, .bicolor_stock:
            fillColor = STColor(srgbRed: 0.72, green: 0.45, blue: 0.20, alpha: 1.0).withAlphaComponent(0.12)
        case .wood, .hardwood, .softwood, .plywood:
            fillColor = STColor.systemBrown.withAlphaComponent(0.08)
        case .plastic, .acrylic, .hdpe, .pvc, .delrin, .epoxy, .bakelite, .synthetic_stone, .polycarbonate:
            fillColor = STColor.systemTeal.withAlphaComponent(0.07)
        case .carbon_fiber:
            fillColor = STColor.systemGray.withAlphaComponent(0.40)
        case .custom:
            fillColor = STColor.systemBlue.withAlphaComponent(0.07)
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
}
