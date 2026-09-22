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

    /// Whether this is being shown as a sheet (needs its own Close button)
    /// or hosted some other way (e.g. a `Settings` scene, which macOS
    /// already gives a window close button).
    var showsCloseButton: Bool = true

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
                Text("Mouse Controls")
            } footer: {
                Text("Pinch to zoom always zooms and can't be reassigned. Snap to Face jumps between the five standard views (bottom excluded), one per swipe, and is only available for scroll inputs.")
            }

            Section {
                Button("Restore Defaults") {
                    settings.restoreDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: showsCloseButton ? 430 : 390)
        .navigationTitle("Canvas Controls")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
