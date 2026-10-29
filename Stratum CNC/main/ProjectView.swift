//
//  ProjectView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 01/09/2026.
//

import SwiftUI

struct ProjectView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var projectModel: ProjectModel
    @ObservedObject private var gCodeStore: GCodeStore

    var onClose: (() -> Void)

    init(appModel: AppModel, projectModel: ProjectModel, onClose: @escaping () -> Void) {
        self.appModel = appModel
        self.projectModel = projectModel
        self.gCodeStore = projectModel.gCodeStore
        self.onClose = onClose
    }

    private var title: String {
        switch projectModel.sessionKind {
            case .project: "Project: \(projectModel.project.name)"
            case .controllerOnly: "Controller"
            case .gcodeFile: gCodeStore.document.fileName
        }
    }

    private var subtitle: String {
        guard projectModel.sessionKind == .project else {
            return ""
        }
        if projectModel.hasUnsavedChanges {
            return "Unsaved…"
        }
        guard let date = projectModel.lastSavedAt else {
            return "Not saved yet"
        }
        return "Saved on \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    var body: some View {

        NavigationStack {

            switch projectModel.activeTab {
                case .cam:
                    CAMView(appModel: appModel, camModel: projectModel.camModel, projectModel: projectModel)
                        .environmentObject(appModel)

                case .controller:
                    ControllerView(model: projectModel.controllerModel,
                                   camModel: projectModel.camModel,
                                   projectModel: projectModel,
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
            // Screen Picker: nothing to switch to without CAM.
            if !projectModel.hidesCAM {
                ToolbarItemGroup(placement: .secondaryAction) {
                    Picker("Screen", selection: $projectModel.activeTab) {
                        ForEach(ActiveTab.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if projectModel.activeTab == .cam {
                ToolbarItem(placement: .primaryAction) {
                    ControlGroup {
                        Button(action: {
                            appModel.showingToolsSheet.toggle()
                        }) {
                            Label {
                                Text("Tools")
                            } icon: {
                                endMillTemplateImage(size: 16)
                            }
                        }
                        .help("Tools library")

                        Button(action: {
                            appModel.showingStocksSheet.toggle()
                        }) {
                            Label("Stock", systemImage: "cube")
                        }
                        .help("Stocks library")
                    }
                    .controlGroupStyle(.navigation)
                }
            }
        }
        // A thin line between the toolbar and the content, so they stay apart on Liquid Glass.
        .overlay(alignment: .top) {
            Divider()
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
    }
}
