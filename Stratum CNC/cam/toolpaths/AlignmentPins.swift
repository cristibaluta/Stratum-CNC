//
//  AlignmentPins.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 05.11.2026.
//
//  Four alignment pins (holes) placed symmetrically around the stock, for registering the
//  stock when it is flipped over to cut another face. They are made as a small DXF file with
//  four circles and go through the normal import (an asset of the project, one object with
//  four paths), so they are saved, reloaded and selected like any imported drawing: one entry
//  in the objects list, each circle selectable on its own on the canvas.
//

import Foundation
import CoreGraphics

enum AlignmentPins {

    /// File name of the generated drawing; it is also the name of the object in the list.
    static let fileName = "Alignment pins.dxf"

    enum PinError: Error, LocalizedError {
        case noStock
        case invalidDiameter
        case outsideStock
        case overlapping

        var errorDescription: String? {
            switch self {
            case .noStock:
                return "Choose a material first: the pins are placed relative to the stock."
            case .invalidDiameter:
                return "The pin diameter must be greater than zero."
            case .outsideStock:
                return "The pins don't fit inside the stock. Increase the distance or reduce the diameter."
            case .overlapping:
                return "The pins would overlap. Reduce the distance from the corner or the diameter."
            }
        }
    }

    /// The centres of the four pins, in canvas mm (stock corner at 0, 0): each one `inset` mm
    /// from the two stock edges of its corner, so they are symmetric about the stock's centre.
    /// Throws a message fit for the dialog when they would not fit.
    static func centers(on stock: StockMaterial?, diameter: Double, inset: Double) throws -> [CGPoint] {
        guard let stock else { throw PinError.noStock }
        guard diameter > 0 else { throw PinError.invalidDiameter }
        let radius = diameter / 2
        let size = stock.footprintSize
        let width = Double(size.width)
        let height = Double(size.height)

        // Whole pin inside the stock, and the pins apart from each other.
        guard inset >= radius else { throw PinError.outsideStock }
        guard width - 2 * inset >= diameter, height - 2 * inset >= diameter else {
            throw PinError.overlapping
        }
        // Round stock is only covered by its bounding square: the pin has to be inside the circle.
        switch stock.geometry {
        case .rectangular:
            break
        case .cylindrical, .disk:
            let reach = hypot(width / 2 - inset, height / 2 - inset) + radius
            guard reach <= width / 2 + 1e-9 else { throw PinError.outsideStock }
        }

        return [CGPoint(x: inset, y: inset),
                CGPoint(x: width - inset, y: inset),
                CGPoint(x: width - inset, y: height - inset),
                CGPoint(x: inset, y: height - inset)]
    }

    /// A minimal R12 DXF with one CIRCLE per centre.
    static func dxf(centers: [CGPoint], diameter: Double) -> String {
        func number(_ value: Double) -> String { String(format: "%.4f", value) }
        var lines = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009", "0", "ENDSEC",
                     "0", "SECTION", "2", "ENTITIES"]
        for center in centers {
            lines += ["0", "CIRCLE", "8", "0",
                      "10", number(Double(center.x)), "20", number(Double(center.y)), "30", "0.0",
                      "40", number(diameter / 2)]
        }
        lines += ["0", "ENDSEC", "0", "EOF"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the drawing to a fresh temporary folder under `fileName` and returns its URL.
    static func writeDrawing(centers: [CGPoint], diameter: Double) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try dxf(centers: centers, diameter: diameter).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
