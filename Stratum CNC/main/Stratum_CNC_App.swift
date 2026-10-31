//
//  Stratum_CNC_App.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 19.08.2026.
//

import SwiftUI

@main
struct Stratum_CNC_App: App {

    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: model, projectsStore: model.projectsStore)
        }
        .defaultSize(width: 1200, height: 800)
        .windowIdealSize(.maximum)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Stratum") {
                    openWindow(id: AboutView.windowID)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    model.showingNewProject = true
                }
                .keyboardShortcut("N", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Save") {
                    model.projectsStore.saveActiveProject()
                }
                .keyboardShortcut("S", modifiers: .command)
            }
        }

        Window("About Stratum", id: AboutView.windowID) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(appModel: model)
        }
    }
}
