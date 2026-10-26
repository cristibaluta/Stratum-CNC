//
//  ProjectsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var projectsStore: ProjectsStore

    private enum PickerKind { case projectFolder, gcode }

    /// What the open file picker is for. Kept after the picker closes (only
    /// `isPicking` flips back), since SwiftUI can dismiss the picker before it
    /// calls the result handler.
    @State private var picker: PickerKind = .projectFolder
    @State private var isPicking = false
    @State private var errorMessage: String?

    private let quickColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 28) {

                // Group 1: ways in that don't start from a saved project.
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("QUICK START")
                    LazyVGrid(columns: quickColumns, spacing: 12) {
                        QuickActionTile(title: "Open Project Folder",
                                        subtitle: "Add a project from disk",
                                        systemImage: "folder") {
                            picker = .projectFolder
                            isPicking = true
                        }
                        QuickActionTile(title: "Try Without Project",
                                        subtitle: "Scratch CAM, nothing saved",
                                        systemImage: "arrow.right.circle") {
                            projectsStore.openZombieProject()
                        }
                        QuickActionTile(title: "Open Controller",
                                        subtitle: "Machine screen, no file loaded",
                                        systemImage: "dial.medium") {
                            projectsStore.openZombieProject(tab: .controller)
                        }
                        QuickActionTile(title: "Import G-code",
                                        subtitle: "Load a file in the Controller",
                                        systemImage: "square.and.arrow.down") {
                            picker = .gcode
                            isPicking = true
                        }
                    }
                }

                // Group 2: the saved projects.
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("PROJECTS")
                LazyVGrid(columns: columns, spacing: 20) {

                    NewProjectCard {
                        appModel.showingNewProject = true
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
                }
              }
                .padding(24)
            }
        }
        .fileImporter(isPresented: $isPicking,
                      allowedContentTypes: picker == .gcode ? GCodeStore.allowedContentTypes : [.folder],
                      allowsMultipleSelection: false) { result in
            handle(result, for: picker)
        }
        .alert("Couldn't open",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationSubtitle("Select or create project...")
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
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appModel.showingNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }

                Button {
                    projectsStore.loadProjects()
                } label: {
                    Label("Refresh Projects", systemImage: "arrow.trianglehead.clockwise.rotate.90")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                AppearanceToggle(isDarkMode: $appModel.isDarkMode)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func handle(_ result: Result<[URL], Error>, for kind: PickerKind) {
        switch result {
            case .failure(let error):
                errorMessage = error.localizedDescription
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }
                switch kind {
                    case .gcode:
                        projectsStore.openZombieProject(gcodeURL: url)
                    case .projectFolder:
                        do {
                            let project = try projectsStore.importProjectFolder(url)
                            projectsStore.open(project)
                        } catch ProjectError.notAProjectFolder {
                            errorMessage = "That folder doesn't contain a project.json, so it isn't a Stratum project."
                        } catch ProjectError.projectAlreadyExists {
                            errorMessage = "A project named “\(url.lastPathComponent)” already exists."
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                }
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
