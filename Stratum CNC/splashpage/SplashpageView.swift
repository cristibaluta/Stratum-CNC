//
//  ProjectsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import UniformTypeIdentifiers
import StratumLink

struct SplashpageView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var projectsStore: ProjectsStore

    @Environment(\.openSettings) private var openSettings

    private enum PickerKind { case projectFolder, gcode }

    /// What the open file picker is for. Kept after the picker closes (only
    /// `isPicking` flips back), since SwiftUI can dismiss the picker before it
    /// calls the result handler.
    @State private var picker: PickerKind = .projectFolder
    @State private var isPicking = false
    @State private var errorMessage: String?

    /// Width of the left column (Quick Start, Libraries, Machines).
    private let sidebarWidth: CGFloat = 344

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16, alignment: .top)
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 32) {

                header

                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 24) {
                        quickStart
                        libraries
                        machines
                    }
                    .frame(width: sidebarWidth)

                    // Only this column scrolls; the header and the left column stay put.
                    projects
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity)

                footer
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AppearanceToggle(isDarkMode: $appModel.isDarkMode)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // The usage tints can be reset on the Appearance tab.
                        SettingsTab.appearance.select()
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open Settings")
                }
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
    }

    // MARK: - Sections

    private var header_: some View {
        HStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("Stratum")
                    .font(.system(size: 30, weight: .bold))
                Text("CAM and Controller for your Makera CNC machine. Set up stock and tools, generate toolpaths, simulate the cut and send the job to your machine, all in one app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 64)

            Text("CAM and Controller for your Makera CNC machine. Set up stock and tools, generate toolpaths, simulate the cut and send the job to your machine, all in one app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 8)
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Quick Start")
            QuickActionGroup {
                QuickActionRow(usageID: .newProject,
                               title: "New Project",
                               subtitle: "Start a new CAM project",
                               systemImage: "plus") {
                    appModel.showingNewProject = true
                }
                QuickActionRow(usageID: .openProjectFolder,
                               title: "Open Project Folder",
                               subtitle: "From a folder on disk",
                               systemImage: "folder") {
                    picker = .projectFolder
                    isPicking = true
                }
                QuickActionRow(usageID: .openController,
                               title: "Open Controller",
                               subtitle: "Connect to your machine",
                               systemImage: "dial.medium") {
                    projectsStore.openZombieProject(tab: .controller)
                }
                QuickActionRow(usageID: .importGCode,
                               title: "Import G-code",
                               subtitle: "Preview and run a file",
                               systemImage: "chevron.left.forwardslash.chevron.right") {
                    picker = .gcode
                    isPicking = true
                }
                QuickActionRow(usageID: .tryWithoutProject,
                               title: "Try Without a Project",
                               subtitle: "Explore without creating a project",
                               systemImage: "arrow.right.circle") {
                    projectsStore.openZombieProject()
                }
            }
        }
    }

    private var libraries: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Libraries")
            QuickActionGroup {
                QuickActionRow(usageID: .toolsLibrary,
                               title: "Tools Library",
                               subtitle: "Your cutting tools",
                               systemImage: "pencil.tip.crop.circle.fill",
                               glyph: AnyView(EndMillIcon(size: 20))) {
                    appModel.showingToolsSheet = true
                }
                QuickActionRow(usageID: .stockLibrary,
                               title: "Stock Library",
                               subtitle: "Your stock materials",
                               systemImage: "cube") {
                    appModel.showingStocksSheet = true
                }
            }
        }
    }

    private var machines: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Machines")
            MachinesSection(discovery: SL.Discovery.shared) {
                projectsStore.openZombieProject(tab: .controller)
            }
        }
        // Listening starts here too: the machines show up before any project is open
        .onAppear { SL.Discovery.shared.startScanningIfNeeded() }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionTitle("Projects")

            if projectsStore.projects.isEmpty {
                Text("No projects yet. Start with New Project.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(projectsStore.projects) { project in
                            ProjectCard(project: project,
                                        previewImage: projectsStore.previewImage(for: project),
                                        stockSummary: projectsStore.stockSummary(for: project))
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

                                    Button(project.isExternal ? "Remove from List" : "Delete", role: .destructive) {
                                        delete(project)
                                    }
                                }
                        }
                    }
                    // Room for the hover shadow and scale, which the scroll view
                    // would otherwise clip at its edges.
                    .padding(6)
                }
                .padding(.horizontal, -6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("This opensource software is work in progress and does not guarantee that all the features work as expected ·")
            Link("For contributions and feedback please visit GitHub",
                 destination: URL(string: "https://github.com/cristibaluta/Stratum-CNC")!)
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
    }

    private func sectionTitle(_ title: String) -> some View {
        // Like a sidebar section header: small, bold, muted
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
    }

    // MARK: - Actions

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
                            let project = try projectsStore.openProjectFolder(url)
                            projectsStore.open(project)
                        } catch ProjectError.notAProjectFolder {
                            errorMessage = "That folder doesn't contain a project.json, so it isn't a Stratum project."
                        } catch ProjectError.projectFolderMissing {
                            errorMessage = "That project's folder can't be reached."
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
        projectsStore.revealInFinder(project)
    }
}
