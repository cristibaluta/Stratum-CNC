//
//  MachineLayout.swift
//  Stratum CNC
//
//  Where the work bed and the anchors sit in the machine's own
//  coordinates (MCS), which is also the frame the controller's canvas is
//  drawn in.
//
//  Home (0, 0) is the bed's top-right corner and the bed extends to
//  `-bedSize` at the bottom-left, so every position on the canvas reads as
//  a real machine coordinate. Three things sit at three places:
//
//      work bed                  fixed:  -bedSize … (0, 0)
//      anchor, stock, axes       at the active anchor's inside corner
//      toolpath, tool, bounds    at the work origin = active anchor + G-code offset
//
//  Only X and Y are in machine coordinates. Z stays relative to the work
//  origin (0 at the top of the stock): the machine's Z offset depends on how
//  the job is touched off, which the canvas doesn't know.
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

    /// The bed's far (bottom-left) corner.
    var bedMin: SIMD2<Float> {
        -bedSize
    }

    /// The bed's home (top-right) corner: machine (0, 0).
    var bedMax: SIMD2<Float> {
        .zero
    }

    /// Machine position of the job's origin: the anchor's inside corner
    /// plus the G-code offset (`CanvasSceneModel.xyOffset`).
    func workOrigin(xyOffset: SIMD2<Float>) -> SIMD2<Float> {
        activeAnchor + xyOffset
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
