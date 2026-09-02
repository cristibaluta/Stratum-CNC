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
        }
        .sheet(isPresented: $appModel.showingStocksSheet) {
            StockSheet(store: appModel.stocksStore)
                .frame(width: 800, height: 600)
        }
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
