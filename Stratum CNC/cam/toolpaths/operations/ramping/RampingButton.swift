//
//  RampingButton.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 29.10.2026.
//

import SwiftUI

/// Same look as `OperationPicker`: a labelled pop-up button that opens the ramping editor.
struct RampingButton: View {
    @Binding var ramping: RampingSettings
    /// The ramp types the operation accepts, in the order they are offered.
    var available: [RampType] = RampType.allCases
    var isCompact: Bool = false
    let action: () -> Void

    private var shownType: RampType { ramping.enabled ? ramping.type : .none }

    var body: some View {
        if isCompact {
            button
                .fixedSize(horizontal: true, vertical: false)
        } else {
            InspectorRow(label: "Entry strategy") {
                button
            }
        }
    }

    private var button: some View {
        Button(action: action) {
            InspectorMenuLabel {
                RampTypeGlyph(type: shownType, tint: ramping.enabled ? .primary : .secondary)
                    .frame(width: 18, height: 14)
                Text(shownType.title)
            }
        }
        .buttonStyle(.plain)
        .help("Entry strategy: how the tool goes down into the material (plunge, linear ramp or helix) and its angle")
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
