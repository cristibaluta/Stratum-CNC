//
//  AnchorChoice.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.10.2026.
//


//
//  MachineLayout.swift
//  Stratum CNC
//
//  Where the work bed and the anchor sit in the machine's own coordinates
//  (MCS), and how that maps onto the canvas.
//
//  The canvas frame has its origin at the *inside corner of the L-bracket*
//  (the active anchor): the stock, the toolpath and the bounding box are
//  drawn from there. The machine's frame is fixed instead — home (0, 0) at
//  the top-right corner of the bed, negative toward the bottom-left — so:
//
//      canvas = machine - activeAnchor
//
//  Choosing another anchor, or changing an anchor's position, therefore
//  moves the *bed* on the canvas, not the stock sitting in the bracket.
//

import Foundation
import simd

/// Which of the machine's two anchors the work is clamped against.
enum AnchorChoice: Int, Codable, CaseIterable, Identifiable {
    case anchor1 = 1
    case anchor2 = 2

    var id: Int { rawValue }

    var label: String {
        "Anchor \(rawValue)"
    }

    var placement: String {
        switch self {
            case .anchor1: return "bottom-left"
            case .anchor2: return "center"
        }
    }
}

struct MachineLayout: Codable, Equatable {

    /// The bed spans `-bedSize` … `(0, 0)` in machine coordinates.
    var bedSize = SIMD2<Float>(200, 200)

    var selected: AnchorChoice = .anchor1

    /// Machine coordinates of each anchor's inside corner. The defaults
    /// reproduce the original drawing — a 15 mm bracket flush with the
    /// bed's bottom-left corner, and a bracket whose corner is at the
    /// bed's center. Enter the machine's real values in the anchor settings.
    var anchor1 = MachineLayout.defaultAnchor1
    var anchor2 = MachineLayout.defaultAnchor2

    static let defaultAnchor1 = SIMD2<Float>(-185, -185)
    static let defaultAnchor2 = SIMD2<Float>(-100, -100)

    /// Inside corner of the anchor in use, in machine coordinates.
    var activeAnchor: SIMD2<Float> {
        selected == .anchor1 ? anchor1 : anchor2
    }

    /// The bed's far (bottom-left) corner on the canvas.
    var bedMinOnCanvas: SIMD2<Float> {
        -bedSize - activeAnchor
    }

    /// The bed's home (top-right, machine 0, 0) corner on the canvas.
    var bedMaxOnCanvas: SIMD2<Float> {
        -activeAnchor
    }

    mutating func resetAnchors() {
        anchor1 = Self.defaultAnchor1
        anchor2 = Self.defaultAnchor2
    }

    // MARK: Persistence

    private static let defaultsKey = "MachineLayout"

    static func load() -> MachineLayout {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let layout = try? JSONDecoder().decode(MachineLayout.self, from: data) else {
            return MachineLayout()
        }
        return layout
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}