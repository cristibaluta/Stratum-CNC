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
- CAMView                                     <- the only place that talks to both CAMModel and ProjectModel;
                                                  funnels values that both sides need to agree on
                                                  (stock visibility) so no other view has to know about both.
    - CAMModel
        - D2_CanvasState (single source of truth for the canvas: objects,
          selection, stock render state, live zoom — everything the
          inspector, material panel and 2D view all read from and write to)
    - ProjectModel (ProjectData)               <- persisted project data
    - CAM_2D_View
        - D2_CanvasNSView
            - D2_CanvasRenderer (based on the properties from D2_CanvasState)
    - ObjectsInspectorView                     <- reads/writes D2_CanvasState via CAMModel.canvasState
    - MaterialPanelView                        <- reads/writes CAMModel.selectedStockMaterial + the shared isStockVisible flag
    - ToolpathListView
*/
struct CAMView: View {

    @ObservedObject var camModel: CAMModel
    @ObservedObject var projectModel: ProjectModel

    var body: some View {
        ZStack {
            if $camModel.canvasState.objects.isEmpty {
                emptyView
            } else {
                // TODO: This view should be swapable with a 3D view depending on the first open file
                // If possible can be only one view for 2D but a converter will generate the NSBezierPaths from any input file
                CAM_2D_View(canvasState: camModel.canvasState,
                            initialViewport: camModel.savedViewport,
                            onViewportChanged: { pan, zoom in
                                camModel.saveViewport(panOffset: pan, zoomScale: zoom)
                            })

                // Align inspector to top-left
                // Align materials and toolpaths to top-right
                HStack {
                    VStack {
                        inspectorPanel
                            .frame(minWidth: 200, maxWidth: 260)
                            .padding(16)
                        Spacer()
                    }
                    Spacer()
//                    VStack {
//                        CanvasZoomToolbar(viewModel: camModel)
//                        Spacer()
//                    }
                    Spacer()
                    VStack(spacing: 16) {
                        MaterialPanelView(stock: $camModel.selectedStockMaterial,
                                          isStockVisible: stockVisibleBinding)
                            .background(.background)// Without a background the CAM_2D_View is displayed above the GroupBox background
                        toolpathsPanel
                            .background(.background)// Without a background the CAM_2D_View is displayed above the GroupBox background
                    }
                    .frame(width: 500)
                    .padding(16)
                }
            }
        }
        .onAppear {
            // Establish the canvas's copy of stock visibility from the
            // persisted value the first time this screen appears.
            camModel.canvasState.isStockVisible = projectModel.projectData.isStockVisible ?? true
        }
        .fileImporter(isPresented: $camModel.showingFilePicker,
                      allowedContentTypes: camModel.supportedFiles,
                      allowsMultipleSelection: false) { result in
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

    /// The single funnel for stock visibility: ProjectData stays the
    /// persisted source of truth, D2_CanvasState stays the render-time
    /// source of truth, and this binding is the one place that keeps them
    /// equal. Nothing else in the app should write either of these directly.
    private var stockVisibleBinding: Binding<Bool> {
        Binding(
            get: { projectModel.projectData.isStockVisible ?? true },
            set: { newValue in
                projectModel.projectData.isStockVisible = newValue
                camModel.canvasState.isStockVisible = newValue
            }
        )
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("No objects added yet!")
                .font(.headline)
                .foregroundColor(.primary)
            Text("File types you can import: SVG, DXF, Gerber (zipped)")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Import") {
                camModel.showingFilePicker = true
            }
            .padding(8)
            Spacer()
        }
    }

    private var inspectorPanel: some View {
        ObjectsInspectorView(
            elements: camModel.canvasState.objects,
            selectedID: camModel.canvasState.selectedObjectIDs.first,
            onSelectionChanged: { id in
                camModel.canvasState.selectObject(id)
            },
            onValueChanged: { id, property, value in
                camModel.canvasState.setValue(value, for: property, objectID: id)
            },
            onNudge: { id, property, amount in
                camModel.canvasState.nudge(id, property: property, amount: amount)
            },
            onScale: { id, factor in
                camModel.canvasState.scaleWidth(id, factor: factor)
            },
            onRotate: { id, degrees in
                camModel.canvasState.rotateObject(id, by: degrees)
            },
            onAddNew: {
                camModel.showingFilePicker = true
            },
            onDelete: { id in
                camModel.canvasState.removeObject(id)
            }
        )
    }

    private var toolpathsPanel: some View {
        GroupBox("TOOLPATHS") {
            ToolpathListView(
                toolpaths: $camModel.toolpaths
            )
        }
    }
}
