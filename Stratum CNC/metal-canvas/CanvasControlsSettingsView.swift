//
//  CanvasControlsSettingsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import SwiftUI

/// Lets the user reassign what each mouse input does on the 3D canvas —
/// orbit, pan, zoom, or nothing — one row per input (plain drag,
/// Shift+drag, middle-click drag, scroll). Reads and writes
/// `CanvasInputSettings.shared` directly, so a change here reaches the
/// canvas immediately; there's no separate "Apply" step.
///
/// Self-contained on purpose: presented as a sheet from `ControllerView`'s
/// toolbar today, but it doesn't assume that — drop it into a `Settings { }`
/// scene instead (for the standard Cmd+, window) and it works unchanged.
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
                        ForEach(CanvasControlAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                }
            } header: {
                Text("Mouse Controls")
            } footer: {
                Text("Pinch to zoom always zooms and can't be reassigned.")
            }

            Section {
                Button("Restore Defaults") {
                    settings.restoreDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: showsCloseButton ? 320 : 280)
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
