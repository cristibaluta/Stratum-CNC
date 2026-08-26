import SwiftUI

struct ContentView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var camModel: CAMModel
    @ObservedObject var controllerModel: ControllerModel

    var body: some View {
        NavigationSplitView {
            MachinesList(model: appModel.controllerModel)
        } detail: {
            switch appModel.activeTab {
                case .projects:
                    ProjectsView(appModel: appModel, projectsModel: appModel.projectsModel)
                case .cam:
                    CAMView(model: appModel.camModel)
                case .controller:
                    ControllerView(model: appModel.controllerModel,
                                   camModel: appModel.camModel,
                                   gCodeModel: appModel.gCodeModel,
                                   joystickStore: appModel.joystick)
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
        .navigationSubtitle(appModel.activeProject?.name ?? "No project selected")
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
