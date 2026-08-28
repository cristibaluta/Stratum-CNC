//
//  RampVisualization.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

// MARK: - Layout constants

enum RampGeometry {
    static let previewSize: CGFloat = 108
    static let detailSize: CGFloat = 320
}

/// How a linear ramp finishes before the main toolpath continues.
enum LinearRampReturnMode: String, CaseIterable, Identifiable {
    case advance = "Continue forward"
    case retrace = "Return to start"
    var id: String { rawValue }
}

/// Spiral direction for a helix ramp.
enum HelixDirection: String, CaseIterable, Identifiable {
    case outsideIn = "Outside → in"
    case insideOut = "Inside → out"
    var id: String { rawValue }
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
    var linearReturnMode: LinearRampReturnMode = .retrace
    var helixDirection: HelixDirection = .outsideIn

    var body: some View {
        switch type {
            case .linear:
                switch mode {
                    case .topPreview:
                        LinearRampTopView(
                            angle: angle,
                            length: length,
                            stepdown: stepdown
                        )
                    case .profileDetail:
                        LinearRampProfileView(
                            angle: angle,
                            length: length,
                            stepdown: stepdown,
                            returnMode: linearReturnMode
                        )
                }
            case .helix:
                switch mode {
                    case .topPreview:
                        HelixTopView(
                            angle: angle,
                            length: length,
                            direction: helixDirection
                        )
                    case .profileDetail:
                        HelixProfileView(
                            angle: angle,
                            length: length,
                            stepdown: stepdown,
                            direction: helixDirection
                        )
                }
            case .none:
                Text("None")
        }
    }
}
