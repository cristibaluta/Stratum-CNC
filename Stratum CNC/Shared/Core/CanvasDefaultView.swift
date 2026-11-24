//
//  CanvasDefaultView.swift
//  Stratum CNC
//
//  The view a canvas opens in when the project has a 3D model (a STEP import). Settings ▸ CAM
//  chooses it; flat work (shapes only) always starts straight down from above.
//

import Foundation

enum CanvasDefaultView: String, CaseIterable, Identifiable {

    /// From the front and the right: +X, −Y, +Z.
    case frontRight
    /// From the front and the left: −X, −Y, +Z.
    case frontLeft
    /// Straight down the Z axis, like the 2D canvas: +Z.
    case top

    var id: String { rawValue }

    static let storageKey = "settings.cam.defaultView"

    /// What the canvas opened with before this was a setting.
    static let fallback = CanvasDefaultView.frontLeft

    static var current: CanvasDefaultView {
        UserDefaults.standard.string(forKey: storageKey).flatMap(CanvasDefaultView.init(rawValue:)) ?? fallback
    }

    var title: String {
        switch self {
            case .frontRight: "X  −Y  Z"
            case .frontLeft: "−X  −Y  Z"
            case .top: "Z"
        }
    }

    var detail: String {
        switch self {
            case .frontRight: "From the front right, Z up"
            case .frontLeft: "From the front left, Z up"
            case .top: "Straight down onto the XY plane"
        }
    }

    func apply(to camera: Camera) {
        switch self {
            case .frontRight:
                camera.setView(eye: SIMD3(0.5, -0.5, 0.7071))
            case .frontLeft:
                camera.setView(eye: SIMD3(-0.5, -0.5, 0.7071))
            case .top:
                camera.snap(to: .top)
        }
    }
}
