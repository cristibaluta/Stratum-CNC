//
//  ProjectsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct ProjectsView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var projectsStore: ProjectsStore

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

                ForEach(projectsStore.projects) { project in
                    ProjectCard(project: project, previewURL: projectsStore.previewURL(for: project))
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
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }

                Button {
                    projectsStore.loadProjects()
                } label: {
                    Label("Refresh Projects", systemImage: "arrow.trianglehead.clockwise.rotate.90")
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
            appModel.camStore.clear()
            let project = try projectsStore.createProject(name: name)
            open(project.0)
        } catch {
            print("Failed to create project: \(error)")
        }
    }

    private func delete(_ project: Project) {
        do {
            try projectsStore.delete(project)
        } catch {
            print("Failed to delete project: \(error)")
        }
    }

    private func open(_ project: Project) {
        // We'll connect this to the CNC editor later.
        print("Opening \(project.name)")
        appModel.openProject(project)
    }

    private func showInFinder(_ project: Project) {
        let url = projectsStore.paths.projectDirectory(for: project)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
