//
//  RampTypeSelector.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import SwiftUI

struct RampTypeSelector: View {

    @Binding var type: RampType

    var angle: Double
    var length: Double
    var stepdown: Double
    var linearReturnMode: LinearRampReturnMode = .retrace
    var helixDirection: HelixDirection = .outsideIn

    private let selectable: [RampType] = [.none, .linear, .helix]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(selectable, id: \.self) { candidate in
                RampTypeCard(
                    type: candidate,
                    angle: angle,
                    length: length,
                    stepdown: stepdown,
                    linearReturnMode: linearReturnMode,
                    helixDirection: helixDirection,
                    isSelected: type == candidate
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        type = candidate
                    }
                }
                .accessibilityAddTraits(type == candidate ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
