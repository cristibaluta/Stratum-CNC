//
//  AlignmentPins.swift
//  Stratum CNC
//
//  Four alignment pins (holes) placed symmetrically around the stock, for registering the
//  stock when it is flipped over to cut another face.
//
//  They are a parametric object: the project stores only the diameter and the offset from the
//  stock's margin, and the object's geometry (four circles, one list entry, each circle
//  selectable on its own) is rebuilt from them whenever either changes or the stock does.
//  They have no position or size of their own, and can't be moved, scaled or rotated.
//

import Foundation
import CoreGraphics
import AppKit
import SwiftDXF
import StratumCAM

/// What defines the pins.
struct AlignmentPinsSpec: Codable, Hashable {
    /// Pin diameter, mm.
    var diameter: Double
    /// From each of the two stock edges of a corner to the pin's centre, mm.
    var offset: Double
}

/// The pins as saved in project.json. The id is the object's id, kept across rebuilds so
/// toolpaths that cut the pins keep pointing at them.
struct AlignmentPinsData: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var diameter: Double
    var offset: Double

    var spec: AlignmentPinsSpec { AlignmentPinsSpec(diameter: diameter, offset: offset) }
}

enum AlignmentPins {

    static let defaultName = "Alignment pins"

    enum PinError: Error, LocalizedError {
        case noStock
        case invalidDiameter
        /// The offset is outside what fits; `range` is nil when no offset fits this diameter.
        case invalidOffset(range: ClosedRange<Double>?)

        var errorDescription: String? {
            switch self {
            case .noStock:
                return "Choose a material first: the pins are placed relative to the stock."
            case .invalidDiameter:
                return "The pin diameter must be greater than zero."
            case .invalidOffset(let range):
                guard let range else {
                    return "Pins that size don't fit this stock. Reduce the diameter."
                }
                func format(_ value: Double) -> String {
                    value.rounded(toPlaces: 3)
                        .formatted(.number.precision(.fractionLength(0...3)).grouping(.never)
                            .locale(Locale(identifier: "en_US")))
                }
                return "For this diameter the offset must be between \(format(range.lowerBound)) and \(format(range.upperBound)) mm."
            }
        }
    }

    /// The offsets at which the pins stay whole inside the stock and apart from each other.
    /// Nil when none does (or the diameter is not positive).
    static func offsetRange(diameter: Double, on stock: StockMaterial) -> ClosedRange<Double>? {
        guard diameter > 0 else { return nil }
        let size = stock.footprintSize
        let width = Double(size.width)
        let height = Double(size.height)
        let radius = diameter / 2

        // Inside the edges, and the pins of a side apart from each other.
        var lower = radius
        let upper = min(width - diameter, height - diameter) / 2
        // Round stock is only covered by its bounding square: the corner pins must be inside the
        // circle, which holds from this offset on (the pins get closer to the centre as it grows).
        switch stock.geometry {
        case .rectangular:
            break
        case .cylindrical, .disk:
            let c = width / 2
            guard c >= radius else { return nil }
            lower = max(lower, c - (c - radius) / 2.0.squareRoot())
        }
        guard lower <= upper + 1e-9 else { return nil }
        return lower...max(lower, upper)
    }

    /// The centres of the four pins, in canvas mm (stock corner at 0, 0): symmetric about the
    /// stock's centre. Throws a message fit for the dialog when they would not fit.
    static func centers(on stock: StockMaterial?, spec: AlignmentPinsSpec) throws -> [CGPoint] {
        guard let stock else { throw PinError.noStock }
        guard spec.diameter > 0 else { throw PinError.invalidDiameter }
        let range = offsetRange(diameter: spec.diameter, on: stock)
        guard let range, range.contains(spec.offset) else { throw PinError.invalidOffset(range: range) }
        let size = stock.footprintSize
        let offset = spec.offset
        return [CGPoint(x: offset, y: offset),
                CGPoint(x: Double(size.width) - offset, y: offset),
                CGPoint(x: Double(size.width) - offset, y: Double(size.height) - offset),
                CGPoint(x: offset, y: Double(size.height) - offset)]
    }

    /// The spec with its offset brought into what fits this stock (after the stock changed), or
    /// nil when the pins no longer fit it at all.
    static func fitted(_ spec: AlignmentPinsSpec, on stock: StockMaterial?) -> AlignmentPinsSpec? {
        guard let stock, let range = offsetRange(diameter: spec.diameter, on: stock) else { return nil }
        var result = spec
        result.offset = min(max(spec.offset, range.lowerBound), range.upperBound)
        return result
    }

    /// The pins as an object. `id` is kept when an existing one is rebuilt or restored.
    static func makeObject(id: UUID = UUID(), name: String, spec: AlignmentPinsSpec,
                           stock: StockMaterial?) throws -> D2_Object {
        let centers = try centers(on: stock, spec: spec)
        let radius = spec.diameter / 2

        var paths: [STBezierPath] = []
        var entities: [DXF.Entity] = []
        var contours: [[SC.Contour]] = []
        for center in centers {
            let x = Double(center.x)
            let y = Double(center.y)
            paths.append(STBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius,
                                                     width: spec.diameter, height: spec.diameter)))
            entities.append(.circle(center: DXF.Point(x, y), radius: radius, layer: "0", color: 256))
            let circle = SC.Contour.Chained(geometry: .circle(center: SIMD2(x, y), radius: radius), reversed: false)
            contours.append([SC.Contour(entities: [circle], isClosed: true)])
        }
        guard let built = ObjectFactory().makeObject(name: name, paths: paths, entities: entities, contours: contours) else {
            throw PinError.invalidDiameter
        }
        let object = D2_Object(id: id, name: name, paths: built.paths, entities: built.entities,
                               contours: built.contours, position: built.position,
                               originalSize: built.originalSize, width: built.width)
        object.alignmentPins = spec
        return object
    }
}
