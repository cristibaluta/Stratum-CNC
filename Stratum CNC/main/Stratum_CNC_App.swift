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
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: model, projectsStore: model.projectsStore)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .windowIdealSize(.maximum)
        .windowResizability(.contentSize)
        #endif
        .commands {
            #if os(macOS)
            CommandGroup(replacing: .appInfo) {
                Button("About Stratum") {
                    openWindow(id: AboutView.windowID)
                }
            }
            #endif
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

        #if os(macOS)
        Window("About Stratum", id: AboutView.windowID) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(appModel: model)
        }
        #endif
    }
}
