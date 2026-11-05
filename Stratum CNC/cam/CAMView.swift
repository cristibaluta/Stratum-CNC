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
          inspector, material panel and canvas all read from and write to)
    - ProjectModel (ProjectData)               <- persisted project data
    - CAM_Metal_View                           <- canvas (Metal), always the free 3D camera; shapes sit flat at z0
        - CAMSceneModel (D2_CanvasState -> [RenderObject] via D2_RenderObjectBuilder)
        - MetalCanvasView
    - STEPInfoPanel                            <- floating over the canvas while there is a STEP model (layers, selection, details)
    - ObjectsInspectorView                     <- reads/writes D2_CanvasState via CAMModel.canvasState
    - MaterialPanelView                        <- reads/writes CAMModel.selectedStockMaterial + the shared isStockVisible flag
    - ToolpathListView                         <- left, under the objects panel: select / show-hide / delete toolpaths
    - ToolpathCellView                         <- right, under the material panel: only while a toolpath is selected
*/
struct CAMView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var camModel: CAMModel
    @ObservedObject var projectModel: ProjectModel
    @State private var fileError: String?
    @State private var showingAlignmentPins = false
    /// Bumped by the fit button to frame the whole scene again.
    @State private var fitRequest = 0

    /// The mouse-icon button opens the Settings window on its Canvas tab, which
    /// edits the same `CanvasInputSettings.shared` as the controller's canvas —
    /// see `CanvasControlsSettingsView`'s doc comment.
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let _ = Self._printChanges()
        ZStack {
            if camModel.canvasState.objects.isEmpty && camModel.stepWorkspace.sources.isEmpty {
                emptyView
            } else {
                // The "Add toolpath" tooltip sits on the selected shapes, inside the canvas
                // view (it needs the camera). Hidden while a toolpath is open.
                // One 3D canvas for everything. Flat shapes (SVG, DXF, Gerber) sit at z0 and start
                // from a top view; with a STEP model it starts from the orbited 3D view.
                CAM_Metal_View(canvasState: camModel.canvasState,
                               zoomModel: camModel.canvasZoomModel,
                               stepScene: camModel.stepWorkspace.activeScene,
                               startsTopDown: !hasSTEP,
                               partFrame: camModel.activeSetupFrame,
                               addToolpathShapeCount: camModel.shapesForNewToolpath.count,
                               canAddToolpathFromEdges: camModel.selectedToolpathID == nil,
                               fitRequest: fitRequest,
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
                        Button {
                            fitRequest &+= 1
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.bordered)
                        .help("Fit to view")

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
                            .panelShadow()
                        toolpathListPanel
                            .panelShadow()
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
                            .panelShadow()
                            .frame(width: 320)
                        // Only while a toolpath is selected in the list
                        if let toolpath = selectedToolpath {
                            VStack(alignment: .trailing, spacing: 10) {
                                toolpathSettingsPanel(for: toolpath)
                                    .panelShadow()
                                toolpathActionsBar
                            }
                            .transition(.opacity)
                            .frame(width: 400)
                        }
                    }
                    .padding(16)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxHeight: .infinity, alignment: .top)
                }

                // The STEP info floats over the canvas, bottom-left, under the
                // other panels. Collapsible, so it can get out of the way.
                if hasSTEP {
                    VStack {
                        Spacer()
                        HStack {
                            STEPInfoPanel(workspace: camModel.stepWorkspace,
                                          onImport: { camModel.showingFilePicker = true },
                                          onReload: { id in
                                              do { try projectModel.reloadSTEPSource(id) }
                                              catch { fileError = String(describing: error) }
                                          },
                                          onRemove: { id in
                                              do { try projectModel.removeSTEPSource(id) }
                                              catch { fileError = String(describing: error) }
                                          })
                                .frame(width: 260)
                                .frame(maxHeight: 340)
                                .panelShadow()
                            Spacer()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear {
            camModel.canvasState.isStockVisible = projectModel.projectData.isStockVisible ?? true
        }
        .alert("File operation failed", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("OK", role: .cancel) { fileError = nil }
        } message: {
            Text(fileError ?? "")
        }
        .sheet(isPresented: $showingAlignmentPins) {
            AlignmentPinsSheet(stock: camModel.canvasState.stock,
                               onCreate: { diameter, offset in
                                   showingAlignmentPins = false
                                   createAlignmentPins(diameter: diameter, offset: offset)
                               },
                               onCancel: { showingAlignmentPins = false })
        }
        .fileImporter(isPresented: $camModel.showingFilePicker,
                      allowedContentTypes: camModel.supportedFiles,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    guard url.startAccessingSecurityScopedResource() else {
                        fileError = "Could not access \(url.lastPathComponent)"
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    // Imports asset to project directory
                    do {
                        let asset = try projectModel.importAsset(from: url)
                        if ProjectModel.isSTEPAsset(asset.name) {
                            try projectModel.loadSTEPAsset(asset, generatePreview: true)
                        } else {
                            camModel.loadAndParseFileAt(projectModel.paths.assetsDirectory.appendingPathComponent(asset.name))
                            projectModel.updatePreview(from: camModel.canvasState.objects)
                        }
                    } catch {
                        fileError = String(describing: error)
                    }
                }

            case .failure(let error):
                fileError = String(describing: error)
            }
        }
    }

    /// Makes the alignment pins: one parametric object (see `AlignmentPins`), saved with the
    /// project as its diameter and offset.
    private func createAlignmentPins(diameter: Double, offset: Double) {
        let taken = Set(camModel.canvasState.objects.map(\.name))
        var name = AlignmentPins.defaultName
        var n = 2
        while taken.contains(name) {
            name = "\(AlignmentPins.defaultName) \(n)"
            n += 1
        }
        do {
            let object = try AlignmentPins.makeObject(name: name,
                                                      spec: AlignmentPinsSpec(diameter: diameter, offset: offset),
                                                      stock: camModel.canvasState.stock)
            camModel.stepWorkspace.selectedModelID = nil
            camModel.canvasState.add(object, select: true)
        } catch {
            fileError = error.localizedDescription
        }
    }

    /// There is a STEP model in the project.
    private var hasSTEP: Bool {
        !camModel.stepWorkspace.sources.isEmpty
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
            Text("File types you can import: STEP, SVG, DXF, Gerber (zipped)")
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
                camModel.stepWorkspace.selectedModelID = nil
                if extend {
                    camModel.canvasState.toggleObjectSelection(id)
                } else if camModel.canvasState.selectedObjectIDs == [id] {
                    // Clicking the selected object again deselects it
                    camModel.canvasState.clearSelection()
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
            onCreateAlignmentPins: {
                showingAlignmentPins = true
            },
            onAlignmentPinsChanged: { id, diameter, offset in
                camModel.canvasState.setAlignmentPins(id, diameter: diameter, offset: offset)
            },
            onDelete: { id in
                camModel.canvasState.removeObject(id)
            },
            onGeneratePreview: { id in
                // Just this object, even while it is hidden on the canvas
                guard let object = camModel.canvasState.object(withID: id) else { return }
                projectModel.updatePreview(from: [object], ignoringVisibility: true)
            },
            stepModels: stepModelItems,
            // A selected 2D object wins: the model's fields only show when none is selected.
            selectedStepModelID: camModel.canvasState.selectedObjectIDs.isEmpty
                ? camModel.stepWorkspace.selectedModelID : nil,
            onSelectStepModel: { id in
                camModel.canvasState.clearSelection()
                camModel.stepWorkspace.selectedModelID = id
                camModel.stepWorkspace.activeID = id
            },
            onToggleStepModelVisibility: { id in
                camModel.stepWorkspace.documents[id]?.isModelVisible.toggle()
            },
            onStepModelValueChanged: { id, axis, value in
                moveSTEPModel(id, axis: axis, to: Float(value))
            },
            onStepModelNudge: { id, axis, amount in
                let workspace = camModel.stepWorkspace
                let current = workspace.position(of: id)
                let value: Float
                switch axis {
                    case .x: value = current.x
                    case .y: value = current.y
                    case .z: value = current.z
                }
                moveSTEPModel(id, axis: axis, to: value + Float(amount))
            },
            onDeleteStepModel: { id in
                do { try projectModel.removeSTEPSource(id) }
                catch { fileError = String(describing: error) }
            }
        )
    }

    private var stepModelItems: [STEPModelItem] {
        let workspace = camModel.stepWorkspace
        return workspace.sources.map { source in
            let scene = workspace.documents[source.id]
            let size = scene?.content.model.bounds.map { bounds in
                SIMD3<Float>(Float(bounds.max.x - bounds.min.x),
                             Float(bounds.max.y - bounds.min.y),
                             Float(bounds.max.z - bounds.min.z))
            }
            return STEPModelItem(id: source.id,
                                 name: source.name,
                                 isVisible: scene?.isModelVisible ?? true,
                                 position: scene == nil ? nil : workspace.position(of: source.id),
                                 size: size)
        }
    }

    private func moveSTEPModel(_ id: UUID, axis: STEPModelAxis, to value: Float) {
        var position = camModel.stepWorkspace.position(of: id)
        switch axis {
            case .x: position.x = value
            case .y: position.y = value
            case .z: position.z = value
        }
        camModel.stepWorkspace.setPosition(position, for: id)
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
            setups: camModel.setups,
            activeSetupID: camModel.activeSetupID,
            // Front, back, left and right need a 3D model: flat shapes only have a top and a bottom
            sideFacesAvailable: hasSTEP,
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
                camModel.moveToolpath(id, toIndexInSetup: index)
            },
            onMoveToSetup: { id, setupID in
                camModel.moveToolpath(id, toSetup: setupID)
            },
            onSelectSetup: { id in
                camModel.activateSetup(id)
            },
            onAddSetup: { face, axis in
                withAnimation(.easeOut(duration: 0.15)) {
                    _ = camModel.addSetup(face: face, axis: axis)
                }
            },
            onSetSetupAxis: { id, axis in
                camModel.setSetupAxis(id, to: axis)
            },
            onDeleteSetup: { id in
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.deleteSetup(id)
                }
            }
        )
    }

    /// Under the toolpath panel: add the next toolpath, or build the program from all the
    /// toolpaths and open it in the Controller.
    private var toolpathActionsBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button {
                projectModel.saveIfNeeded()
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.addToolpath()
                }
            } label: {
                Label("Next toolpath", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .help("Add another toolpath")

            PreviewInControllerButton(gCodeStore: projectModel.gCodeStore) {
                projectModel.saveIfNeeded()
                projectModel.previewInController()
            }
        }
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

private extension View {
    /// Opaque rounded card with a soft shadow, so the panels float above the canvas.
    func panelShadow() -> some View {
        background(.background, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .secondary.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}

/// Same look as the Controller's "Refresh from CAM" button: prominent, with the refresh
/// icon, and a spinner while the program is being generated.
private struct PreviewInControllerButton: View {

    @ObservedObject var gCodeStore: GCodeStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if gCodeStore.isGeneratingFromCAM {
                ProgressView().controlSize(.small)
            } else {
                Label("Preview in Controller", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(gCodeStore.isGeneratingFromCAM)
        .help("Generate all toolpaths and open them in the Controller")
    }
}
