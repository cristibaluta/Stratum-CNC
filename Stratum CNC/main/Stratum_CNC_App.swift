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

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: model,
                        projectsModel: model.projectsStore,
                        camStore: model.camStore,
                        controllerModel: model.controllerStore)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    // Add your new project logic here
                }
                .keyboardShortcut("N", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Save") {
                    // Add your save logic here
                }
                .keyboardShortcut("S", modifiers: .command)
            }
        }
    }
}
