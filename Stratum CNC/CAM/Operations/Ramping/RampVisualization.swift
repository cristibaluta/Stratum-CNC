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
            case .none:
                switch mode {
                    case .topPreview:       PlungeTopView()
                    case .profileDetail:    Text(type.title)
                }
        }
    }
}

/// A plunge seen from above: the tool goes down at one point, so it is a dot with a ring
/// that spreads out from it, in the same animated style as the linear and helix previews.
private struct PlungeTopView: View {
    private let cycleDuration: Double = 2.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation) { timeline in
                let currentPhase = phase(for: timeline.date, cycleDuration: cycleDuration)
                Canvas { context, _ in
                    draw(context: &context, size: size, phase: currentPhase)
                }
            }
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, phase: CGFloat) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = (min(size.width, size.height) / 2 - 2) * 0.85

        // The tool's footprint, the way the helix preview draws its outline.
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - outerRadius * 0.45, y: center.y - outerRadius * 0.45,
                                   width: outerRadius * 0.9, height: outerRadius * 0.9)),
            with: .color(.secondary.opacity(0.4)),
            lineWidth: 1
        )

        // A ring spreading from the point the tool goes down at.
        let ring = outerRadius * 0.45 * phase
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)),
            with: .color(.accentColor.opacity(0.6 * (1 - phase))),
            lineWidth: 2
        )
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
            with: .color(.accentColor)
        )
    }
}
