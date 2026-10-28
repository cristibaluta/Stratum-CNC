//
//  RampingButton.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// Same look as `OperationPicker`: a labelled pop-up button that opens the ramping editor.
struct RampingButton: View {
    @Binding var ramping: RampingSettings
    /// The ramp types the operation accepts, in the order they are offered.
    var available: [RampType] = RampType.allCases
    let action: () -> Void

    private var shownType: RampType { ramping.enabled ? ramping.type : .none }

    var body: some View {
        InspectorRow(label: "Entry") {
            Button(action: action) {
                InspectorMenuLabel {
                    RampTypeGlyph(type: shownType, tint: ramping.enabled ? .primary : .secondary)
                        .frame(width: 18, height: 14)
                    Text(ramping.enabled ? ramping.type.rawValue : "Off")
                }
            }
            .buttonStyle(.plain)
            .help("Ramp angle, length, return path and spiral direction")
        }
    }
}

private extension RampType {
    var rampSelectionHint: String {
        switch self {
            case .none:   return "The tool plunges straight down."
            case .linear: return "The tool descends at an angle before cutting."
            case .helix:  return "The tool spirals down to depth."
        }
    }
}

#Preview {
    @Previewable @State var ramping = RampingSettings(enabled: true, type: .helix, angle: 3, length: 10)
    RampingButton(ramping: $ramping) {}
        .padding()
}
