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

/*
- CAMView
    - CAMModel
        - D2_CanvasState (all the properties and states of the drawing area)
    - ProjectModel (ProjectData)
    - CAM_2D_View
        - D2_CanvasNSView
            - D2_CanvasRenderer (based on the properties from D2_CanvasState)
    - ObjectsInspectorView
    - MaterialPanelView
    - ToolpathListView
*/
struct CAMView: View {

    @ObservedObject var camModel: CAMModel
    @ObservedObject var projectModel: ProjectModel

    var body: some View {
        ZStack {
            if camModel.objects.isEmpty {
                emptyView
            } else {
                // TODO: This view should be swapable with a 3D view depending on the first open file
                // If possible can be only one view for 2D but a converter will generate the NSBezierPaths from any input file
                CAM_2D_View(model: camModel)

                HStack {
                    VStack {
                        ObjectsInspectorView(
                            elements: camModel.objects,
                            selectedID: nil,
                            onSelectionChanged: { id in
                                //                            selectedID = id
                            },
                            onValueChanged: { id, property, value in
                                // update your D2_Object
                            },
                            onNudge: { id, property, amount in
                                // nudge your object
                            },
                            onScale: { id, factor in
                                // scale your object
                            },
                            onRotate: { id, degrees in
                                // rotate your object
                            },
                            onAddNew: {
                                // add object
                            },
                            onDelete: { id in
                                // delete object
                            }
                        )
                        .frame(minWidth: 100, maxWidth: 200)
                        .padding(16)
                        Spacer()
                    }
                    Spacer()
                    VStack(spacing: 16) {
                        MaterialPanelView(projectData: $projectModel.projectData,
                                          stock: $camModel.selectedStockMaterial)
                            .background(.background)// Without a background the CAM_2D_View is displayed above the GroupBox background
                            .frame(width: 500)
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
                    // Imports asset to project directory
                    if let _ = try? projectModel.importAsset(from: url) {
                        // If success, load the asset into UI
                        // We must use the same original url to load the file because security scope does not work in app dirs
                        camModel.loadAndParseFileAt(url)
                    }
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
