import SwiftUI

struct ContentView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var projectsModel: ProjectsStore
    @ObservedObject var controllerModel: ControllerStore

    var body: some View {
        NavigationSplitView {
            MachinesList(model: appModel.controllerStore)
        } detail: {
            switch appModel.activeTab {
                case .projects:
                    ProjectsView(appModel: appModel, projectsStore: appModel.projectsStore)
                case .cam:
                    CAMView(model: appModel.camStore, projectsModel: appModel.projectsStore)
                case .controller:
                    ControllerView(model: appModel.controllerStore,
                                   camModel: appModel.camStore,
                                   gCodeModel: appModel.gCodeStore,
                                   joystickStore: appModel.joystickStore)
            }
        }
        .toolbar {
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
        .navigationSubtitle(projectsModel.activeProject?.name ?? "No project selected")
        .onChange(of: controllerModel.selectedMachine) { _, newValue in
            // Once we're actually talking to a machine over TCP, stop the UDP
            // broadcast listener — leaving it running alongside an active
            // connection is what triggers the repeated NECP "File exists"
            // flow-churn errors in Console.
            if newValue != nil {
                controllerModel.discovery.stopScanning()
            }
        }
    }
}
