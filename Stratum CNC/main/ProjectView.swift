//
//  ProjectView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 01/09/2026.
//

import SwiftUI

struct ProjectView: View {

    @ObservedObject var projectModel: ProjectModel

    var onClose: (() -> Void)

    var body: some View {
        NavigationStack {
            switch projectModel.activeTab {
                case .cam:
                    CAMView(camModel: projectModel.camModel)
                case .controller:
                    ControllerView(model: projectModel.controllerModel,
                                   camModel: projectModel.camModel,
                                   gCodeModel: projectModel.gCodeStore,
                                   joystickStore: projectModel.joystickStore)
            }
        }
        .toolbar {
            // Close project
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    onClose()
                }) {
                    Label("Close Project", systemImage: "arrow.backward")
                }
            }
            // Screen Picker
            ToolbarItemGroup(placement: .secondaryAction) {
                Picker("Active tab", selection: $projectModel.activeTab) {
                    ForEach(ActiveTab.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle(projectModel.project.name)
        .navigationSubtitle("Status...")
    }
}
