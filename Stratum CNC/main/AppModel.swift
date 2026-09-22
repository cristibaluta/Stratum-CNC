//
//  MainModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.08.2026.
//

import SwiftUI

@MainActor
class AppModel: ObservableObject {

    @Published var projectsStore = ProjectsStore()
    @Published var toolsStore = ToolsStore()
    @Published var stocksStore = StocksStore()

    @Published var showingToolsSheet: Bool = false
    @Published var showingStocksSheet: Bool = false

    /// App-wide day/night switch. Drives `.preferredColorScheme` for the
    /// whole app from the root (`ContentView`), so every screen — Projects,
    /// CAM, Controller — follows the same explicit choice instead of each
    /// screen deciding its own appearance. Persisted, like the other
    /// standing preferences in this app.
    @Published var isDarkMode: Bool = UserDefaults.standard.bool(forKey: "app.isDarkMode") {
        didSet { UserDefaults.standard.set(isDarkMode, forKey: "app.isDarkMode") }
    }
}
