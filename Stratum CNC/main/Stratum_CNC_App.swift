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
            CommandGroup(after: .windowArrangement) {
                Button("Tool Library") {
                    openWindow(id: LibraryWindow.toolsID)
                }
                .keyboardShortcut("T", modifiers: [.command, .option])
                Button("Stock Library") {
                    openWindow(id: LibraryWindow.stocksID)
                }
                .keyboardShortcut("S", modifiers: [.command, .option])
            }
            #endif
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    model.showingNewProject = true
                }
                .keyboardShortcut("N", modifiers: .command)

                Menu("Open Recent Project") {
                    RecentItemsMenuContent(history: model.projectsStore.history, kind: .project) {
                        model.projectsStore.openHistoryEntry($0)
                    }
                }
                Menu("Open Recent G-code") {
                    RecentItemsMenuContent(history: model.projectsStore.history, kind: .gcode) {
                        model.projectsStore.openHistoryEntry($0)
                    }
                }
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

        // Browse/edit workspaces: non-modal, resizable, and the canvas stays usable next to them.
        // Picking a tool or stock still happens in the popovers of the toolpath panels.
        Window("Tool Library", id: LibraryWindow.toolsID) {
            ToolLibraryWindowContent(appModel: model)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1080, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Window("Stock Library", id: LibraryWindow.stocksID) {
            StockLibraryWindowContent(appModel: model)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(appModel: model)
        }
        #endif
    }
}
