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
                        QuickActionTile(title: "New Project",
                                        subtitle: "Start a new CAM project",
                                        systemImage: "plus") {
                            appModel.showingNewProject = true
                        }
                        QuickActionTile(title: "Open Project Folder",
                                        subtitle: "Open a Stratum project from a folder on disk",
                                        systemImage: "folder") {
                            picker = .projectFolder
                            isPicking = true
                        }
                        QuickActionTile(title: "Try Without Project",
                                        subtitle: "Explore CAM without creating a saved project",
                                        systemImage: "arrow.right.circle") {
                            projectsStore.openZombieProject()
                        }
                        QuickActionTile(title: "Open Controller",
                                        subtitle: "Connect to and control the CNC machine",
                                        systemImage: "dial.medium") {
                            projectsStore.openZombieProject(tab: .controller)
                        }
                        QuickActionTile(title: "Import G-code",
                                        subtitle: "Load a G-code file in the Controller to preview and run",
                                        systemImage: "chevron.left.forwardslash.chevron.right") {
                            picker = .gcode
                            isPicking = true
                        }
                    }
                }

                // Group 2: shared libraries.
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("LIBRARIES")
                    LazyVGrid(columns: quickColumns, spacing: 12) {
                        QuickActionTile(title: "Tools Library",
                                        subtitle: "Browse and edit your cutting tools",
                                        systemImage: "pencil.tip.crop.circle.fill",
                                        iconRotation: .degrees(180)) {
                            appModel.showingToolsSheet = true
                        }
                        QuickActionTile(title: "Stock Library",
                                        subtitle: "Browse and edit your stock materials",
                                        systemImage: "cube") {
                            appModel.showingStocksSheet = true
                        }
                    }
                }

                // Group 3: the saved projects.
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("PROJECTS")
                LazyVGrid(columns: columns, spacing: 20) {

                    // The New Project card used to be the first cell here; it now
                    // lives in Quick Start as a tile. `NewProjectCard` is kept
                    // as-is, so putting it back is just un-commenting this.
                    // NewProjectCard {
                    //     appModel.showingNewProject = true
                    // }

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
