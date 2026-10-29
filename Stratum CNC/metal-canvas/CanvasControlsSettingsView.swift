//
//  CanvasControlsSettingsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import SwiftUI

struct CanvasControlsSettingsView: View {
    @ObservedObject private var settings = CanvasInputSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(CanvasInputTrigger.allCases) { trigger in
                    Picker(trigger.label, selection: binding(for: trigger)) {
                        ForEach(CanvasControlAction.allCases.filter { $0.isAvailable(for: trigger) }) { action in
                            Text(action.label).tag(action)
                        }
                    }
                }
            } header: {
                Text("Mouse & Trackpad Controls")
            } footer: {
                Text("Pinch to zoom always zooms and can't be reassigned. Snap to Face jumps between the five standard views (bottom excluded).")
            }

            Section {
                Button("Restore Defaults") {
                    settings.restoreDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Stratum CNC Settings")
    }

    private func binding(for trigger: CanvasInputTrigger) -> Binding<CanvasControlAction> {
        Binding(
            get: { settings.action(for: trigger) },
            set: { settings.setAction($0, for: trigger) }
        )
    }
}

#Preview {
    CanvasControlsSettingsView()
}
