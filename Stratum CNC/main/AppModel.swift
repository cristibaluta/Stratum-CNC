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
}
