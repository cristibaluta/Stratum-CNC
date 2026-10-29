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
    let helixDirection: HelixDirection
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.rampCardBackground))
                // A plunge is drawn from above as the single point the tool goes down at.
                RampVisualization(
                    type: type,
                    angle: angle,
                    length: length,
                    stepdown: stepdown,
                    mode: .topPreview,
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
            Text(type.title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
    }
}
