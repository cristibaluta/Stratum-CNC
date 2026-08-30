//
//  ProjectsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct ProjectsView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var projectsModel: ProjectsModel

    @State private var showingNewProject = false

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {

                NewProjectCard {
                    showingNewProject = true
                }

                ForEach(projectsModel.projects) { project in
                    ProjectCard(project: project, previewURL: projectsModel.previewURL(for: project))
                        .onTapGesture(count: 2) {
                            open(project)
                        }
                        .onTapGesture(count: 1) {
                            print("select project \(project.name)")
                        }
                        .contextMenu {
                            Button("Open") {
                                open(project)
                            }

                            Button("Show in Finder") {
                                showInFinder(project)
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                delete(project)
                            }
                        }
                }
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet { name in
                createProject(name: name)
            }
        }
    }

    private func createProject(name: String) {
        do {
            let project = try projectsModel.createProject(name: name)
            open(project)
        } catch {
            print("Failed to create project: \(error)")
        }
    }

    private func delete(_ project: ProjectData) {
        do {
            try projectsModel.delete(project)
        } catch {
            print("Failed to delete project: \(error)")
        }
    }

    private func open(_ project: ProjectData) {
        // We'll connect this to the CNC editor later.
        print("Opening \(project.name)")
        projectsModel.activeProject = project
    }

    private func showInFinder(_ project: ProjectData) {
        let url = projectsModel.directoryURL(for: project)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
