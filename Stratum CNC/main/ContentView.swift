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
                SplashpageView(appModel: appModel, projectsStore: projectsStore)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // On every screen, the Projects list included
//        .toolbar {
//            ToolbarItem(placement: .primaryAction) {
//                ActivityMonitorView(monitor: appModel.activityMonitor)
//            }
//        }
        .sheet(isPresented: $appModel.showingNewProject) {
            // `folder` is nil for a project managed by the app; errors are thrown
            // back so the sheet can stay open and show them.
            NewProjectSheet { name, folder in
                let project = try projectsStore.createProject(name: name, in: folder)
                projectsStore.open(project)
            }
        }
        // `onDismiss` also fires after a normal pick, but by then the continuation
        // is already resolved, so resolving again with nil is a no-op.
        .sheet(isPresented: $appModel.showingToolsSheet, onDismiss: { appModel.resolveToolPick(nil) }) {
            // Only pass `onPick` when someone is awaiting a tool; otherwise the
            // sheet is opened to browse/edit the library and shows no "Pick" button.
            ToolsSheet(store: appModel.toolsStore,
                       onPick: appModel.isPickingTool ? { appModel.resolveToolPick($0) } : nil)
                .frame(width: 800, height: 600)
                .preferredColorScheme(appModel.isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $appModel.showingStocksSheet, onDismiss: { appModel.resolveStockPick(nil) }) {
            StockSheet(store: appModel.stocksStore, onPick: { appModel.resolveStockPick($0) })
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            projectsStore.saveActiveProject()
        }
    }
}
