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
    - CAM_Metal_View                           <- canvas (Metal), replaced CAM_2D_View (CoreAnimation) in step 6
        - CAMSceneModel (D2_CanvasState -> [RenderObject] via D2_RenderObjectBuilder)
        - MetalCanvasView (.locked2D)
    - ObjectsInspectorView                     <- reads/writes D2_CanvasState via CAMModel.canvasState
    - MaterialPanelView                        <- reads/writes CAMModel.selectedStockMaterial + the shared isStockVisible flag
    - ToolpathListView                         <- left, under the objects panel: select / show-hide / delete toolpaths
    - ToolpathCellView                         <- right, under the material panel: only while a toolpath is selected
*/
struct CAMView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var camModel: CAMModel
    @ObservedObject var projectModel: ProjectModel

    /// The mouse-icon button opens the Settings window on its Canvas tab, which
    /// edits the same `CanvasInputSettings.shared` as the controller's canvas —
    /// see `CanvasControlsSettingsView`'s doc comment and `CanvasInteractionMode.locked2D`.
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let _ = Self._printChanges()
        ZStack {
            if $camModel.canvasState.objects.isEmpty {
                emptyView
            } else {
                // The "Add toolpath" tooltip sits on the selected shapes, inside the canvas
                // view (it needs the camera). Hidden while a toolpath is open.
                CAM_Metal_View(canvasState: camModel.canvasState,
                               zoomModel: camModel.canvasZoomModel,
                               addToolpathShapeCount: camModel.shapesForNewToolpath.count,
                               onAddToolpath: {
                                   withAnimation(.easeOut(duration: 0.15)) {
                                       camModel.addToolpathFromSelection()
                                   }
                               })
                    .id(ObjectIdentifier(camModel.canvasState))

                // Centered at the bottom of the canvas, above everything else.
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        CanvasZoomButton(zoomModel: camModel.canvasZoomModel)

                        Button {
                            SettingsTab.canvas.select()
                            openSettings()
                        } label: {
                            Image(systemName: "computermouse")
                        }
                        .buttonStyle(.bordered)
                        .help("Mouse Controls")
                    }
                    .padding(.bottom, 16)
                }

                // Align inspector to top-left
                // Align materials and toolpaths to top-right
                HStack {
                    VStack(spacing: 12) {
                        inspectorPanel
                        toolpathListPanel
                        Spacer()
                    }
                    .frame(minWidth: 200, maxWidth: 260)
                    .padding(16)
                    Spacer()
//                    VStack {
//                        CanvasZoomToolbar(viewModel: camModel)
//                        Spacer()
//                    }
                    Spacer()
                    ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .trailing, spacing: 16) {
                        PanelStockMaterial(stock: $camModel.selectedStockMaterial,
                                           isStockVisible: stockVisibleBinding,
                                           isCompact: true,
                                           stocksStore: appModel.stocksStore)
                            .background(.background)// Without a background the canvas is displayed above the GroupBox background
                            .frame(width: 320)
                        // Only while a toolpath is selected in the list
                        if let toolpath = selectedToolpath {
                            toolpathSettingsPanel(for: toolpath)
                                .background(.background)// Without a background the canvas is displayed above the GroupBox background
                                .transition(.opacity)
                                .frame(width: 400)
                        }
                    }
                    .padding(16)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .onAppear {
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
                    if let asset = try? projectModel.importAsset(from: url) {
                        camModel.loadAndParseFileAt(projectModel.paths.assetsDirectory.appendingPathComponent(asset.name))
                        // The object is on the canvas now: take the project card's picture from it
                        projectModel.updatePreview(from: camModel.canvasState.objects)
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
        PanelObjectsInspector(
            elements: camModel.canvasState.objects,
            selectedIDs: camModel.canvasState.selectedObjectIDs,
            selectionBounds: camModel.canvasState.selectionBounds,
            onSelectionChanged: { id, extend in
                if extend {
                    camModel.canvasState.toggleObjectSelection(id)
                } else {
                    camModel.canvasState.selectObject(id)
                }
            },
            onToggleVisibility: { id in
                camModel.canvasState.toggleObjectVisibility(id)
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
            onGroupValueChanged: { property, value in
                camModel.canvasState.setSelectionValue(value, for: property)
            },
            onGroupNudge: { property, amount in
                switch property {
                    case .x: camModel.canvasState.moveSelection(dx: amount, dy: 0)
                    case .y: camModel.canvasState.moveSelection(dx: 0, dy: amount)
                    default: break
                }
            },
            onGroupScale: { factor in
                camModel.canvasState.scaleSelection(factor: factor)
            },
            onAddNew: {
                camModel.showingFilePicker = true
            },
            onDelete: { id in
                camModel.canvasState.removeObject(id)
            }
        )
    }

    /// The toolpath open in the settings panel, if any. Looked up by id on every
    /// render so a toolpath removed behind our back (project reload) just closes the panel.
    private var selectedToolpath: ToolpathData? {
        guard let id = camModel.selectedToolpathID else {
            return nil
        }
        return camModel.toolpaths.first { $0.id == id }
    }

    private var toolpathListPanel: some View {
        PanelToolpaths(
            toolpaths: camModel.toolpaths,
            selectedID: camModel.selectedToolpathID,
            hiddenIDs: camModel.hiddenToolpathIDs,
            onSelect: { id in
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.toggleToolpathSelection(id)
                }
            },
            onToggleVisibility: { id in
                camModel.toggleToolpathVisibility(id)
            },
            onDelete: { id in
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.deleteToolpath(id)
                }
            },
            onAdd: {
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.addToolpath()
                }
            },
            onMove: { id, index in
                camModel.moveToolpath(id, to: index)
            }
        )
    }

    private func toolpathSettingsPanel(for toolpath: ToolpathData) -> some View {
        PanelToolpathDetails(toolpath: binding(for: toolpath),
                             stockMaterial: camModel.selectedStockMaterial.material,
                             stockThickness: camModel.selectedStockMaterial.thickness,
                             siblingNames: Set(camModel.toolpaths.filter { $0.id != toolpath.id }.map(\.name)),
                             isPicking: camModel.pickingToolpathID == toolpath.id,
                             generation: camModel.generations[toolpath.id],
                             isGenerating: camModel.generatingIDs.contains(toolpath.id),
                             restSource: toolpath.operation.restSourceID.flatMap { sourceID in
                                 camModel.toolpaths.first { $0.id == sourceID }
                             },
                             showsRestAreas: $camModel.showsRestAreas,
                             onCreateRest: {
                                 projectModel.saveIfNeeded()
                                 camModel.addRestToolpath(from: toolpath.id)
                             },
                             onGenerate: {
                                 projectModel.saveIfNeeded()
                                 camModel.generateToolpaths(for: toolpath.id)
                             },
                             onScrub: { step in
                                 camModel.setToolpathScrubStep(step)
                             },
                             onDone: {
                                projectModel.saveIfNeeded()
                                withAnimation(.easeOut(duration: 0.15)) {
                                    camModel.selectedToolpathID = nil
                                }
                             },
                             onDelete: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    camModel.deleteToolpath(toolpath.id)
                                }
                             },
                             onAddNext: {
                                projectModel.saveIfNeeded()
                                camModel.addToolpath()
                             },
                             targetShapes: {
                                // Read when asked (the holding tabs popover), not on every redraw
                                let targets = camModel.toolpaths.first { $0.id == toolpath.id }?.targets ?? []
                                return targets.compactMap { target in
                                    camModel.canvasState.object(withID: target.objectID)?
                                        .worldCGPath(forPathAt: target.pathIndex)
                                }
                             }
        )
        .id(toolpath.id)
    }

    /// Edits go straight into `camModel.toolpaths`, looked up by id (not index)
    /// so the binding stays safe if the array changes while a field is being edited.
    private func binding(for toolpath: ToolpathData) -> Binding<ToolpathData> {
        let id = toolpath.id
        return Binding(
            get: { camModel.toolpaths.first { $0.id == id } ?? toolpath },
            set: { newValue in
                if let index = camModel.toolpaths.firstIndex(where: { $0.id == id }) {
                    camModel.toolpaths[index] = newValue
                }
            }
        )
    }

}

/// A vertical ScrollView that is only as tall as its content — up to whatever
/// height it's offered, beyond which it scrolls. A plain ScrollView always grabs
/// all the space it's given, which would turn the settings panel into a
/// full-height slab even for a short toolpath.
//private struct FittingScrollView<Content: View>: View {
//
//    private let content: Content
//    @State private var contentHeight: CGFloat?
//
//    init(@ViewBuilder content: () -> Content) {
//        self.content = content()
//    }
//
//    var body: some View {
//        ScrollView {
//            content
//                .background(
//                    GeometryReader { proxy in
//                        Color.clear
//                            .onChange(of: proxy.size.height, initial: true) { _, height in
//                                contentHeight = height
//                            }
//                    }
//                )
//        }
//        // Until the content has been measured, take what's offered
//        .frame(maxHeight: contentHeight ?? .infinity)
//    }
//}
