//
//  CanvasInitialZoom.swift
//  Stratum CNC
//
//  How a CAM canvas is zoomed the first time it frames the project. Settings ▸ CAM chooses it.
//  The "Fit to view" button on the canvas always fits, whatever this says.
//

import Foundation

/// The part of the canvas that isn't covered by panels, as the margins they leave (points).
/// A fit centres the model in what remains.
struct CanvasFitInsets: Equatable {
    var left: CGFloat = 0
    var right: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

enum CanvasInitialZoom: String, CaseIterable, Identifiable {

    /// The model fills the room between the panels, centred there.
    case fit
    /// True to life (100%: 1 mm of the part is 1 mm on screen), centred between the panels.
    case trueToLife

    var id: String { rawValue }

    static let storageKey = "settings.cam.initialZoom"
    static let fallback = CanvasInitialZoom.fit

    static var current: CanvasInitialZoom {
        UserDefaults.standard.string(forKey: storageKey).flatMap(CanvasInitialZoom.init(rawValue:)) ?? fallback
    }

    var title: String {
        switch self {
            case .fit: "Fit to view"
            case .trueToLife: "100%"
        }
    }

    var detail: String {
        switch self {
            case .fit: "The model fills the free area between the panels"
            case .trueToLife: "True to life: 1 mm of the part is 1 mm on screen"
        }
    }
}

/// What a fit needs to know about the content, measured along the camera's own axes.
struct CanvasContentExtents {
    var min: SIMD3<Float>
    var max: SIMD3<Float>
    /// Extent along the camera's right direction.
    var right: ClosedRange<Float>
    /// Extent along the camera's up direction.
    var up: ClosedRange<Float>
}
