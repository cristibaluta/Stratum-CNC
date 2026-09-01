import SwiftUI

struct ContentView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var projectsStore: ProjectsStore

    var body: some View {
        Group {
            if let projectModel = projectsStore.activeProjectModel {
                ProjectView(projectModel: projectModel, onClose: {
                    projectsStore.activeProject = nil
                    projectsStore.activeProjectModel = nil
                })
            } else {
                NavigationStack {
                    ProjectsView(projectsStore: projectsStore)
                }
                .navigationSubtitle("Select or create project...")
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    appModel.showingToolsSheet.toggle()
                }) {
                    Label("Tools", systemImage: "pencil.tip.crop.circle.fill")
                }
                .rotationEffect(.degrees(180))

                Button(action: {
                    appModel.showingStocksSheet.toggle()
                }) {
                    Label("Stock", systemImage: "cube")
                }
            }
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
