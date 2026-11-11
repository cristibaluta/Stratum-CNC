//
//  OpenSettings.swift
//  Stratum CNC
//
//  `openSettings` exists on macOS only (it opens the Settings scene). This gives the views
//  one call that works on both: the Settings window on macOS, a sheet on iOS.
//  `ContentView` applies `settingsPresenter(_:)` once, at the root.
//

import SwiftUI

private struct OpenSettingsKey: EnvironmentKey {
    static var defaultValue: () -> Void { {} }
}

extension EnvironmentValues {
    /// Opens the app's settings. Use as `@Environment(\.stOpenSettings) var openSettings`, then `openSettings()`.
    var stOpenSettings: () -> Void {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}

private struct SettingsPresenter: ViewModifier {

    @ObservedObject var appModel: AppModel
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .environment(\.stOpenSettings, { openSettings() })
        #else
        content
            .environment(\.stOpenSettings, { appModel.showingSettings = true })
            .sheet(isPresented: $appModel.showingSettings) {
                NavigationStack {
                    SettingsView(appModel: appModel)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { appModel.showingSettings = false }
                            }
                        }
                }
            }
        #endif
    }
}

extension View {
    func settingsPresenter(_ appModel: AppModel) -> some View {
        modifier(SettingsPresenter(appModel: appModel))
    }
}
