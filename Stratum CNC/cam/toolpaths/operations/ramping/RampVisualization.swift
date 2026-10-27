//
//  RampVisualization.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

enum RampGeometry {
    static let previewSize: CGFloat = 108
    static let detailSize: CGFloat = 320
}

enum HelixDirection: String, CaseIterable, Identifiable {
    case outsideIn = "Outside → in"
    case insideOut = "Inside → out"
    var id: String {
        rawValue
    }
}

// MARK: - Visualization mode

enum RampVisualizationMode {
    case topPreview
    case profileDetail
}

struct RampVisualization: View {
    let type: RampType
    let angle: Double
    let length: Double
    var stepdown: Double = 1
    var mode: RampVisualizationMode
    var helixDirection: HelixDirection = .insideOut

    var body: some View {
        switch type {
            case .linear:
                switch mode {
                    case .topPreview:       LinearRampTopView(angle: angle, length: length, stepdown: stepdown)
                    case .profileDetail:    LinearRampProfileView(angle: angle, length: length, stepdown: stepdown)
                }
            case .helix:
                switch mode {
                    case .topPreview:       HelixTopView(direction: helixDirection)
                    case .profileDetail:    HelixProfileView(angle: angle, length: length, stepdown: stepdown, direction: helixDirection)
                }
            case .none:                     Text("None")
        }
    }
}
