//
//  CAMView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

// The main view of the CAM screen.
// It holds the objects to model and the list of toolpaths
// You can access also the tools lib and stocks lib from the toolbar

struct CAMView: View {

    @ObservedObject var camModel: CAMModel
//    @ObservedObject var projectsStore: ProjectsStore

    var body: some View {
        ZStack {
            if camModel.files.isEmpty {
                emptyView
            } else {
                // TODO: This view should be swapable with a 3D view depending on the first open file
                // If possible can be only one view for 2D but a converter will generate the NSBezierPaths from any input file
                CAM_2D_View(model: camModel)

                HStack {
                    Spacer()
                    VStack(spacing: 16) {
//                        MaterialPanelView(project: $projectsStore.activeProjectData, stock: $camStore.selectedStockMaterial)
//                            .background(.background)// Without a background the CAM_2D_View is displayed above the GroupBox background
//                            .frame(width: 500)
                        toolpathsPanel
                            .background(.background)// Without a background the CAM_2D_View is displayed above the GroupBox background
                            .frame(width: 500)
                    }
                    .padding(16)
                }
            }
        }
        .fileImporter(isPresented: $camModel.showingFilePicker, allowedContentTypes: [.svg], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    guard url.startAccessingSecurityScopedResource() else {
                        print("Could not access:", url)
                        return
                    }
//                    if let _ = try? projectsStore.importAsset(from: url) {
//                        camStore.loadAndParseFileAt(url)
//                    }
                    url.stopAccessingSecurityScopedResource()
                }

            case .failure(let error):
                print("Failed:", error)
            }
        }
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("No objects added yet!")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("Import SVG") {
                camModel.showingFilePicker = true
            }
            Spacer()
        }
    }

    var toolpathsPanel: some View {
        GroupBox("TOOLPATHS") {
            ToolpathListView(model: camModel)
                .frame(maxWidth: .infinity)
        }
    }
}
