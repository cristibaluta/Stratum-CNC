//
//  CAMModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

@MainActor
class CAMModel: ObservableObject {

    @Published var toolStore = ToolStore()
    @Published var showingToolsSheet: Bool = false

    @Published var stockStore = StockStore()
    @Published var showingStockSheet: Bool = false

    // Insert new files. temporary vars to use
    @Published var showingFilePicker = false
    @Published var files: [CAM_File] = []
    @Published var toolpaths: [ToolpathData] = []

    func loadAndParseFileAt(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Could not access:", url)
            return
        }
        defer {
            url.stopAccessingSecurityScopedResource()
        }

        print("URL:", url)

        guard let paths = try? SVGParser().parseFileAt(url) else {
            return
        }
        files.append(
            CAM_File(url: url, paths: paths)
        )
    }
}
