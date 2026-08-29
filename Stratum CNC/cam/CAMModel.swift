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

    @Published var selectedStockMaterial = StockMaterial(
        name: "Workpiece",
        material: .aluminum,
        geometry: .rectangular(width: 100, height: 50, depth: 10)
    )

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
        toolpaths = demoToolpaths
    }

    let demoToolpaths: [ToolpathData] = [
        ToolpathData(
            name: "Aluminum Inside Pocket",
            tool: Tool(name: "3.175*12mm", shankDiameter: 3.175, toolDiameter: 3.175, length: 12, type: .endMill),
            startZ: 0.0,
            endZ: -3.0,
            contour: .inside,
            ramping: RampingSettings(
                enabled: true,
                type: .helix,
                angle: 3.0,
                length: 5.0
            ),
            feedRate: 500,
            plungeRate: 200,
            spindleRPM: 12000,
            stepDown: 0.5,
            stepOver: 0.4,
            safeZ: 5.0
        ),

        ToolpathData(
            name: "Hardwood Outside Contour",
            tool: Tool(name: "3.175*12mm", shankDiameter: 3.175, toolDiameter: 3.175, length: 12, type: .endMill),
            startZ: 0.0,
            endZ: -6.0,
            contour: .outside,
            ramping: RampingSettings(
                enabled: true,
                type: .linear,
                angle: 5.0,
                length: 10.0
            ),
            feedRate: 1000,
            plungeRate: 300,
            spindleRPM: 10000,
            stepDown: 1.0,
            stepOver: 0.8,
            safeZ: 5.0
        ),

        ToolpathData(
            name: "Plastic Outline",
            tool: Tool(name: "3.175*12mm", shankDiameter: 3.175, toolDiameter: 3.175, length: 12, type: .endMill),
            startZ: 0.0,
            endZ: -4.0,
            contour: .outline,
            ramping: RampingSettings(
                enabled: false,
                type: .none,
                angle: 0,
                length: 0
            ),
            feedRate: 800,
            plungeRate: 250,
            spindleRPM: 10000,
            stepDown: 0.75,
            stepOver: 0.5,
            safeZ: 3.0
        )
    ]
}
