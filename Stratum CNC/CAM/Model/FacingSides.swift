//
//  FacingSides.swift
//  Stratum CNC
//
//  Which sides of a facing's area the passes run past. A facing covers the bounding box of the
//  selected shapes plus its extension length; with a side switched off the passes stop at the
//  box's edge on that side. Stored on `OperationSettings`, so it is saved with the project.
//
//  The sides are named the way the canvas shows them (top view, Y up): "front" is the low-Y edge,
//  "back" the high-Y one. `SetupFrame.placeFlat(_: FacingSides)` turns them into the setup's own
//  coordinates (a bottom setup is mirrored).
//

import Foundation
import CoreGraphics

struct FacingSides: Codable, Hashable {

    var left = true
    var right = true
    /// The low-Y edge.
    var front = true
    /// The high-Y edge.
    var back = true

    /// Every side extended: the facing as it always was.
    static let all = FacingSides()

    private enum CodingKeys: String, CodingKey {
        case left, right, front, back
    }

    enum Side: String, CaseIterable, Identifiable {
        case left, right, front, back

        var id: String { rawValue }

        var title: String {
            switch self {
                case .left:  return "Left"
                case .right: return "Right"
                case .front: return "Front"
                case .back:  return "Back"
            }
        }
    }

    subscript(_ side: Side) -> Bool {
        get {
            switch side {
                case .left:  return left
                case .right: return right
                case .front: return front
                case .back:  return back
            }
        }
        set {
            switch side {
                case .left:  left = newValue
                case .right: right = newValue
                case .front: front = newValue
                case .back:  back = newValue
            }
        }
    }

    var isAll: Bool {
        left && right && front && back
    }

    var isNone: Bool {
        !(left || right || front || back)
    }

    /// The sides that are extended, in the order the editor lists them.
    var extended: [Side] {
        Side.allCases.filter { self[$0] }
    }

    /// "All sides", "No sides" or "Left, Back".
    var summary: String {
        if isAll { return "All sides" }
        if isNone { return "No sides" }
        return extended.map(\.title).joined(separator: ", ")
    }

    /// `box` grown by `length` on the extended sides only. The one place that says what the
    /// facing covers: the popover draws it and the generator cuts it.
    func area(of box: CGRect, extendedBy length: Double) -> CGRect {
        let d = CGFloat(max(length, 0))
        let minX = box.minX - (left ? d : 0)
        let maxX = box.maxX + (right ? d : 0)
        let minY = box.minY - (front ? d : 0)
        let maxY = box.maxY + (back ? d : 0)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension FacingSides {

    /// Every key is optional so projects saved before this existed (all sides) still open.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        left = try c.decodeIfPresent(Bool.self, forKey: .left) ?? true
        right = try c.decodeIfPresent(Bool.self, forKey: .right) ?? true
        front = try c.decodeIfPresent(Bool.self, forKey: .front) ?? true
        back = try c.decodeIfPresent(Bool.self, forKey: .back) ?? true
    }
}
