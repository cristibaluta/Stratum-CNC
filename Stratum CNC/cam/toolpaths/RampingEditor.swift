//
//  RampingEditor.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct RampingEditor: View {
    @Binding var ramping: RampingSettings

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        Form {

            Toggle(
                "Enable ramping",
                isOn: $ramping.enabled
            )

            if ramping.enabled {

                Picker(
                    "Ramp type",
                    selection: $ramping.type
                ) {
                    ForEach(RampType.allCases, id: \.self) {
                        Text($0.rawValue)
                    }
                }

                HStack {
                    Text("Ramp angle")
                    Spacer()

                    TextField(
                        "",
                        value: $ramping.angle,
                        format: .number
                    )
                    .multilineTextAlignment(.trailing)

                    Text("°")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Ramp length")
                    Spacer()

                    TextField(
                        "",
                        value: $ramping.length,
                        format: .number
                    )
                    .multilineTextAlignment(.trailing)

                    Text("mm")
                        .foregroundStyle(.secondary)
                }

                Text(rampDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var rampDescription: String {
        switch ramping.type {
        case .none:
            return "The tool plunges vertically."

        case .linear:
            return "The tool gradually descends along a linear ramp."

        case .helix:
            return "The tool descends while moving around the contour."

        case .zigZag:
            return "The tool descends using alternating ramp passes."
        }
    }
}
