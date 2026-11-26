//
//  FacingSides.swift
//  Stratum CNC
//
//  How far a facing's passes run past each side of its area. A facing covers the bounding box of
//  the selected shapes plus, on every side, that side's own extension length (0 by default: the
//  passes stop at the box's edge). Stored on `OperationSettings`, so it is saved with the project.
//
//  The sides are named the way the canvas shows them (top view, Y up): "front" is the low-Y edge,
//  "back" the high-Y one. `SetupFrame.placeFlat(_: FacingSides)` turns them into the setup's own
//  coordinates (a bottom setup is mirrored).
//

import Foundation
import CoreGraphics

struct FacingSides: Codable, Hashable {

    /// The most a side can be extended, mm (what the library accepts for an extension).
    static let maxLength: Double = 50

    /// The extension of each side, mm.
    var left: Double = 0
    var right: Double = 0
    /// The low-Y edge.
    var front: Double = 0
    /// The high-Y edge.
    var back: Double = 0

    /// No side extended: the facing covers the selection's box.
    static let none = FacingSides()

    /// The same length on every side.
    static func all(_ length: Double) -> FacingSides {
        FacingSides(left: length, right: length, front: length, back: length)
    }

    fileprivate enum CodingKeys: String, CodingKey {
        case left, right, front, back
    }

    enum Side: String, CaseIterable, Identifiable {
        case left, right, front, back

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
                case .left:  return "Left"
                case .right: return "Right"
                case .front: return "Front"
                case .back:  return "Back"
            }
        }
    }

    subscript(_ side: Side) -> Double {
        get {
            switch side {
                case .left:  return left
                case .right: return right
                case .front: return front
                case .back:  return back
            }
        }
        set {
            let length = min(max(newValue, 0), Self.maxLength)
            switch side {
                case .left:  left = length
                case .right: right = length
                case .front: front = length
                case .back:  back = length
            }
        }
    }

    /// Nothing is extended.
    var isNone: Bool {
        !(left > 0 || right > 0 || front > 0 || back > 0)
    }

    /// The sides that are extended, in the order the editor lists them.
    var extended: [Side] {
        Side.allCases.filter { self[$0] > 0 }
    }

    /// "No extension" or "Left 2, Back 1.5" (mm).
    var summary: String {
        if isNone {
            return "No extension"
        }
        return extended.map { "\($0.title) \(Self.format(self[$0]))" }.joined(separator: ", ")
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// `box` grown on every side by that side's own length. The one place that says what the
    /// facing covers: the popover draws it and the generator cuts it.
    func area(of box: CGRect) -> CGRect {
        let minX = box.minX - CGFloat(max(left, 0))
        let maxX = box.maxX + CGFloat(max(right, 0))
        let minY = box.minY - CGFloat(max(front, 0))
        let maxY = box.maxY + CGFloat(max(back, 0))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension FacingSides {

    /// Every key is optional so older projects still open.
    init(from decoder: Decoder) throws {
        try self.init(from: decoder, legacyLength: 1)
    }

    /// Projects saved when a facing had one extension length for all sides, and a checkbox for
    /// each side, have a true / false per side: a ticked side gets `legacyLength`.
    init(from decoder: Decoder, legacyLength: Double) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func length(_ key: CodingKeys) throws -> Double {
            if let value = try? c.decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let ticked = try c.decodeIfPresent(Bool.self, forKey: key) {
                return ticked ? legacyLength : 0
            }
            // Missing: a project saved before the sides existed extended every side
            return legacyLength
        }
        left = try length(.left)
        right = try length(.right)
        front = try length(.front)
        back = try length(.back)
    }
}
