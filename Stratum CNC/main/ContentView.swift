//
//  ContentView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 19.08.2026.
//

import SwiftUI

struct ContentView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var projectsStore: ProjectsStore

    var body: some View {
        Group {
            if let projectModel = projectsStore.activeProjectModel {
                ProjectView(appModel: appModel, projectModel: projectModel, onClose: {
                    projectsStore.close()
                })
            } else {
                ProjectsView(appModel: appModel, projectsStore: projectsStore)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $appModel.showingToolsSheet) {
            ToolsSheet(store: appModel.toolsStore)
                .frame(width: 800, height: 600)
                .preferredColorScheme(appModel.isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $appModel.showingStocksSheet) {
            StockSheet(store: appModel.stocksStore)
                .frame(width: 800, height: 600)
                .preferredColorScheme(appModel.isDarkMode ? .dark : .light)
        }
        // Single source of truth for the whole app's appearance. Every
        // screen reads `\.colorScheme` from this environment (the CAM
        // canvas included — see `CAM_Metal_View`), so setting it once here
        // is enough to flip light/dark everywhere at once. Sheets are
        // presented in their own hierarchy on macOS, so they re-assert it
        // above rather than relying on inheriting it from here.
        .preferredColorScheme(appModel.isDarkMode ? .dark : .light)
    }
}
//        .onChange(of: controllerModel.selectedMachine) { _, newValue in
//            // Once we're actually talking to a machine over TCP, stop the UDP
//            // broadcast listener — leaving it running alongside an active
//            // connection is what triggers the repeated NECP "File exists"
//            // flow-churn errors in Console.
//            if newValue != nil {
//                controllerModel.discovery.stopScanning()
//            }
//        }
