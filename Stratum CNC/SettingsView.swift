//
//  SettingsTab.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.10.2026.
//


//
//  SettingsView.swift
//  Stratum CNC
//
//  The app's Settings window (Stratum CNC ▸ Settings…, ⌘,). App-wide
//  preferences live here: the light/dark appearance and the canvas mouse
//  controls. The canvases' mouse button opens this window on the Canvas tab.
//

import SwiftUI

enum SettingsTab: String {
    case appearance
    case canvas

    static let storageKey = "settings.selectedTab"

    /// Makes the Settings window show this tab the next time it appears (or
    /// right away if it's already open). Pair with `openSettings()`.
    func select() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
}

struct SettingsView: View {

    @ObservedObject var appModel: AppModel
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .appearance
    @State private var confirmingUsageReset = false

    var body: some View {
        TabView(selection: $selectedTab) {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                .tag(SettingsTab.appearance)

            // `showsCloseButton: false`: the Settings window has its own close button.
            CanvasControlsSettingsView()
                .tabItem { Label("Canvas", systemImage: "computermouse") }
                .tag(SettingsTab.canvas)
        }
        .frame(width: 420, height: 500)
        // The Settings window is its own scene, outside ContentView, so it has
        // to apply the app-wide appearance itself.
        .preferredColorScheme(appModel.isDarkMode ? .dark : .light)
    }

    private var appearanceTab: some View {
        Form {
            Section {
                Picker("Theme", selection: $appModel.isDarkMode.animation(.easeOut(duration: 0.15))) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }

            Section {
                Text("The icons on the Quick Start and Libraries buttons of the projects page are tinted by how often you use them. The button you click most gets the full accent color, rarely used ones stay plain, and the rest fall in between. Recent clicks count more than old ones, so the tints follow your habits as they change.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reset Usage Tints…", role: .destructive) {
                    confirmingUsageReset = true
                }
            } header: {
                Text("Button Usage")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset button usage?",
                            isPresented: $confirmingUsageReset) {
            Button("Reset", role: .destructive) {
                QuickActionUsage.shared.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All Quick Start and Libraries icons go back to the plain, untinted look and start learning again from zero.")
        }
    }
}
