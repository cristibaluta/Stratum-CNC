//
//  ProjectsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct ProjectsView: View {

    @ObservedObject var projectsStore: ProjectsStore

    @State private var showingNewProject = false

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
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

                    HStack {
                        Spacer()
                        Button {
                            projectsStore.openZombieProject()
                        } label: {
                            Label("Try without project", systemImage: "arrow.right.circle.fill")
                        }
                        Spacer()
                    }
                }
                .padding(24)
            }
        }
        .navigationSubtitle("Select or create project...")
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
            let project = try projectsStore.createProject(name: name)
            open(project)
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
        projectsStore.open(project)
    }

    private func showInFinder(_ project: Project) {
        guard let paths = try? ProjectPaths(project: project) else {
            return
        }
        let url = paths.projectDirectory
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
