//
//  MakeraStudio_LiteApp.swift
//  MakeraStudio Lite
//
//  Created by Cristian Baluta on 19.08.2026.
//

import SwiftUI

@main
struct CNC_StudioApp: App {

    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: model,
                        camModel: model.camModel,
                        controllerModel: model.controllerModel)
        }
        .windowResizability(.contentSize)
    }
}
