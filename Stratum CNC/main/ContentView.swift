import SwiftUI

struct ContentView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var projectsModel: ProjectsStore
    @ObservedObject var camStore: CAMStore
    @ObservedObject var controllerModel: ControllerStore

    var body: some View {
        if let _ = projectsModel.activeProject {
            activeProjectView
        } else {
            projectsSelectorView
        }
    }

    private var projectsSelectorView: some View {
        NavigationStack {
            ProjectsView(appModel: appModel, projectsStore: appModel.projectsStore)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    appModel.camStore.showingToolsSheet.toggle()
                }) {
                    Label("Tools", systemImage: "pencil.tip.crop.circle.fill")
                }
                .rotationEffect(.degrees(180))

                Button(action: {
                    appModel.camStore.showingStockSheet.toggle()
                }) {
                    Label("Stock", systemImage: "cube")
                }
            }
        }
        .navigationSubtitle("Select or create project...")
        .sheet(isPresented: $camStore.showingToolsSheet) {
            ToolsSheet(store: camStore.toolStore)
                .frame(width: 800, height: 600)
        }
        .sheet(isPresented: $camStore.showingStockSheet) {
            StockSheet(store: camStore.stockStore)
                .frame(width: 800, height: 600)
        }
    }

    private var activeProjectView: some View {
        NavigationStack {
            switch appModel.activeTab {
                case .cam:
                    CAMView(camStore: appModel.camStore, projectsStore: appModel.projectsStore)
                case .controller:
                    ControllerView(model: appModel.controllerStore,
                                   camModel: appModel.camStore,
                                   gCodeModel: appModel.gCodeStore,
                                   joystickStore: appModel.joystickStore)
            }
        }
        .toolbar {
            // Close project
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    appModel.projectsStore.activeProject = nil
                    appModel.projectsStore.activeProjectData = nil
                }) {
                    Label("Close Project", systemImage: "arrow.backward")
                }
            }
            // Screen Picker
            ToolbarItemGroup(placement: .secondaryAction) {
                Picker("Active tab", selection: $appModel.activeTab) {
                    ForEach(ActiveTab.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle(projectsModel.activeProject?.name ?? "No project selected")
        .navigationSubtitle("Status...")
        .sheet(isPresented: $camStore.showingToolsSheet) {
            ToolsSheet(store: camStore.toolStore)
                .frame(width: 800, height: 600)
        }
        .sheet(isPresented: $camStore.showingStockSheet) {
            StockSheet(store: camStore.stockStore)
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
