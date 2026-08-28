//
//  RampTypeCard.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

struct RampTypeCard: View {
    let type: RampType
    let angle: Double
    let length: Double
    let stepdown: Double
    let linearReturnMode: LinearRampReturnMode
    let helixDirection: HelixDirection
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.rampCardBackground))
                // For `.none` this renders as a plain empty box — no icon, by design.
                RampVisualization(
                    type: type,
                    angle: angle,
                    length: length,
                    stepdown: stepdown,
                    mode: .topPreview,
                    linearReturnMode: linearReturnMode,
                    helixDirection: helixDirection
                )
                .padding(10)
            }
            .frame(width: RampGeometry.previewSize, height: RampGeometry.previewSize)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 6, y: 2)
            Text(type.rawValue)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
    }
}
