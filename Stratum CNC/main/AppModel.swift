//
//  MainModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.08.2026.
//

import SwiftUI

enum ActiveTab: String, CaseIterable, Identifiable {
    case cam = "CAM"
    case controller = "Controller"

    var id: String {
        rawValue
    }
}

@MainActor
class AppModel: ObservableObject {

    @Published var activeTab: ActiveTab = .cam

    // Tabs. Models should be in memory at all times, so we don't loose data when switching from one tab to another
    @Published var projectsStore = ProjectsStore()
    @Published var camStore = CAMStore()
    @Published var controllerStore = ControllerStore()

    @Published var gCodeStore = GCodeStore()
    @Published var joystickStore = GameControllerStore()

    func openProject(_ project: Project) {
        // Set as active project
        projectsStore.activeProject = project
        // Load project data
        let projectData = try? projectsStore.loadProjectData(for: project)
        projectsStore.activeProjectData = projectData

        // 1. Switch to CAM screen
        activeTab = .cam
        camStore.clear()

        // 2. Load material
        if let stock = projectData?.stock {
            camStore.selectedStockMaterial = stock
        }

        // 3. Load assets and import into CAM
        for asset in projectData?.assets ?? [] {
            let url = projectsStore.paths.assetsDirectory(for: project).appendingPathComponent(asset.name)
            camStore.loadAndParseFileAt(url)
        }

        // 4. Load toolpaths and display in CAM
        let toolpathsUrl = projectsStore.paths.toolpathsFile(for: project)
        print(toolpathsUrl)
    }
}
