//
//  MainModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.08.2026.
//

import SwiftUI

enum ActiveTab: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case cam = "CAM"
    case controller = "Controller"

    var id: String {
        rawValue
    }
}

@MainActor
class AppModel: ObservableObject {

    @Published var activeTab: ActiveTab = .projects

    // Tabs. Models should be in memory at all times, so we don't loose data when switching from one tab to another
    @Published var projectsModel = ProjectsModel()
    @Published var camModel = CAMModel()
    @Published var controllerModel = ControllerModel()
    @Published var gCodeModel = GCodeModel()

    @Published var joystick = GameControllerStore()
}
