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

    var body: some View {
        TabView(selection: $selectedTab) {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                .tag(SettingsTab.appearance)

            // `showsCloseButton: false`: the Settings window has its own close button.
            CanvasControlsSettingsView(showsCloseButton: false)
                .tabItem { Label("Canvas", systemImage: "computermouse") }
                .tag(SettingsTab.canvas)
        }
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
            } footer: {
                Text("Applies to every screen: Projects, CAM and Controller.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 390)
    }
}
