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
    - CAMLayersOverlay                         <- legend over the canvas, bottom-left (shapes, model, stock, toolpaths, anchor, axes): show / hide, plus Z0 projections; the toolpaths row is the All toolpaths switch
    - ObjectsInspectorView                     <- reads/writes D2_CanvasState via CAMModel.canvasState
    - MaterialPanelView                        <- reads/writes the active setup's stock (CAMModel.activeStock: its own, or CAMModel.selectedStockMaterial) + the shared isStockVisible flag
    - ToolpathListView                         <- left, under the objects panel: select / show-hide / delete toolpaths
    - ToolpathCellView                         <- right, under the material panel: only while a toolpath is selected
*/
struct CAMView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var camModel: CAMModel
    @ObservedObject var projectModel: ProjectModel
    @State private var fileError: String?
    @State private var showingAlignmentPins = false
    /// Changes when a setup on a different stock is added, which opens the stock panel's details.
    @State private var stockPanelExpandTrigger: UUID?
    /// Bumped by the fit button to frame the whole scene again.
    @State private var fitRequest = 0
    /// How tall the legend (bottom-left) is right now; the left panels' scroll stops above it.
    @State private var legendHeight: CGFloat = 0
    /// The widths of the panels over the canvas, so a fit centres the model in the free area between them
    @State private var leftPanelsWidth: CGFloat = 292
    @State private var rightPanelsWidth: CGFloat = 352

    /// The mouse-icon button opens the Settings window on its Canvas tab, which
    /// edits the same `CanvasInputSettings.shared` as the controller's canvas —
    /// see `CanvasControlsSettingsView`'s doc comment.
    @Environment(\.stOpenSettings) private var openSettings

    var body: some View {
        let _ = Self._printChanges()
        Group {
            if camModel.canvasState.objects.isEmpty && camModel.stepWorkspace.sources.isEmpty {
                emptyView
            } else {
                camView
            }
        }
        .alert("File operation failed", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("OK", role: .cancel) { fileError = nil }
        } message: {
            Text(fileError ?? "")
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
                    defer {
                        url.stopAccessingSecurityScopedResource()
                    }
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

    private var camView: some View {
        ZStack {
            CAM_Metal_View(canvasState: camModel.canvasState,
                           zoomModel: camModel.canvasZoomModel,
                           stepWorkspace: camModel.stepWorkspace,
                           startsTopDown: !hasSTEP,
                           partFrame: camModel.activeSetupFrame,
                           addToolpathShapeCount: camModel.shapesForNewToolpath.count,
                           canAddToolpathFromEdges: camModel.selectedToolpathID == nil,
                           fitRequest: fitRequest,
                           fitInsets: CanvasFitInsets(left: leftPanelsWidth, right: rightPanelsWidth,
                                                      top: 16, bottom: 16),
                           // A selected 2D object wins, like in the objects list
                           selectedStepModelID: camModel.canvasState.selectedObjectIDs.isEmpty
                               ? camModel.stepWorkspace.selectedModelID : nil,
                           selectedStepBody: camModel.canvasState.selectedObjectIDs.isEmpty
                               ? camModel.stepWorkspace.selectedModelID.flatMap { camModel.stepWorkspace.body(ofModel: $0) }
                               : nil,
                           onMoveStepModel: { id, dx, dy in
                               var position = camModel.stepWorkspace.position(of: id)
                               position.x += Float(dx)
                               position.y += Float(dy)
                               camModel.stepWorkspace.setPosition(position, for: id)
                           },
                           onDeselectStepModel: {
                               camModel.stepWorkspace.selectedModelID = nil
                           },
                           onEmptyDoubleClick: {
                               // Closes the open toolpath's details, like its Done button
                               guard camModel.selectedToolpathID != nil else {
                                   return
                               }
                               projectModel.saveIfNeeded()
                               withAnimation(.easeOut(duration: 0.15)) {
                                   camModel.selectedToolpathID = nil
                               }
                           },
                           onAddToolpath: {
                               withAnimation(.easeOut(duration: 0.15)) {
                                   camModel.addToolpathFromSelection()
                               }
                           },
                           onAddStepToolpath: { operation in
                               withAnimation(.easeOut(duration: 0.15)) {
                                   camModel.addToolpathFromSelection(operation: operation)
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

                    // The options are shared by every file on the canvas
                    let stepScenes = camModel.stepWorkspace.loadedScenes
                    if let primary = stepScenes.first(where: \.hasSurfaces) ?? stepScenes.first {
                        STEPDisplayOptionsButton(scene: primary,
                                                 others: stepScenes.filter { $0 !== primary })
                    }

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
            HStack(alignment: .top) {
                // Scrolls when the two panels are taller than the room above the legend, which
                // stays where it is (bottom-left): the scroll view ends right over it.
                FittingScrollView {
                    VStack(spacing: 12) {
                        inspectorPanel
                        toolpathListPanel
                    }
                    .frame(minWidth: 200, maxWidth: 260)
                    .padding(16)
                }
                .frame(minWidth: 232, maxWidth: 292)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    leftPanelsWidth = $0
                }
                // The legend's own bottom margin (16) and its height
                .padding(.bottom, legendHeight + 16)
                .frame(maxHeight: .infinity, alignment: .top)
                Spacer()
//                    VStack {
//                        CanvasZoomToolbar(viewModel: camModel)
//                        Spacer()
//                    }
                Spacer()
                // The scroll view takes the whole height it is given, so it is only there while
                // a toolpath's settings are open (the column can then be taller than the window).
                // Without it the stock panel is all there is, and the empty space under it
                // passes clicks and scrolls to the canvas.
                if let toolpath = selectedToolpath {
                    // The preview is not part of the scrolling column: always in view, top-left
                    // of the settings, so a change can be checked without scrolling to it.
                    toolpathPreviewPanel(for: toolpath)
                        .frame(width: 260)
                        .padding(.top, 16)
                        .frame(maxHeight: .infinity, alignment: .top)
                    ScrollView(.vertical, showsIndicators: true) {
                        rightPanels
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    rightPanels
                        .fixedSize(horizontal: true, vertical: false)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.width
                        } action: {
                            rightPanelsWidth = $0
                        }
                }
            }

            // The canvas's objects list (and the Z0 projections option): only what this
            // project's canvas has. Floats at the canvas's bottom-left.
            VStack {
                Spacer()
                HStack {
                    CAMLayersOverlay(canvasState: camModel.canvasState,
                                     workspace: camModel.stepWorkspace,
                                     isStockVisible: stockVisibleBinding,
                                     showsAllToolpaths: $camModel.showsAllToolpaths,
                                     hasToolpaths: !camModel.toolpaths.isEmpty)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        legendHeight = $0
                    }
                    Spacer()
                }
            }
            .padding(16)
        }
        .onAppear {
            camModel.canvasState.isStockVisible = projectModel.projectData.isStockVisible ?? true
        }
        .sheet(isPresented: $showingAlignmentPins) {
            AlignmentPinsSheet(stock: camModel.canvasState.stock,
                               onCreate: { diameter, offset in
                                   showingAlignmentPins = false
                                   createAlignmentPins(diameter: diameter, offset: offset)
                               },
                               onCancel: { showingAlignmentPins = false })
        }
    }

    /// The stock panel, and the selected toolpath's settings under it.
    private var rightPanels: some View {
        VStack(alignment: .trailing, spacing: 16) {
            PanelStockMaterial(stock: activeStockBinding,
                               isStockVisible: stockVisibleBinding,
                               isCompact: true,
                               stocksStore: appModel.stocksStore,
                               scopeTag: stockScopeTag,
                               onUseProjectStock: camModel.activeSetupHasOwnStock ? {
                                   camModel.setSetupStock(camModel.activeSetupID, to: nil)
                               } : nil,
                               onUseOwnStock: (!camModel.activeSetupHasOwnStock && camModel.setups.count > 1) ? {
                                   // Starts as a copy of the project's stock; its fields open to edit
                                   camModel.setSetupStock(camModel.activeSetupID, to: camModel.selectedStockMaterial)
                                   stockPanelExpandTrigger = UUID()
                               } : nil,
                               warning: camModel.activeStockWarning,
                               expandTrigger: stockPanelExpandTrigger)
                .frame(width: 320)
            // Only while a toolpath is selected in the list
            if let toolpath = selectedToolpath {
                toolpathSettingsPanel(for: toolpath)
                .transition(.opacity)
                .frame(width: 320)
            }
        }
        .padding(16)
    }

    /// The stock panel edits the active setup's stock: its own when it has one, the project's otherwise.
    private var activeStockBinding: Binding<StockMaterial> {
        Binding(get: { camModel.activeStock },
                set: { camModel.setActiveStock($0) })
    }

    /// Marks the stock panel while it edits a stock that belongs to the active setup alone.
    private var stockScopeTag: String? {
        camModel.activeSetupHasOwnStock ? "This setup only" : nil
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
                guard let object = camModel.canvasState.object(withID: id) else {
                    return
                }
                projectModel.updatePreview(from: [object], ignoringVisibility: true)
            },
            stepModels: stepModelItems,
            // A selected 2D object wins: the model's fields only show when none is selected.
            selectedStepModelID: camModel.canvasState.selectedObjectIDs.isEmpty
                ? camModel.stepWorkspace.selectedModelID : nil,
            onSelectStepModel: { id in
                camModel.canvasState.clearSelection()
                if camModel.stepWorkspace.selectedModelID == id {
                    // Clicking the selected model again deselects it
                    camModel.stepWorkspace.selectedModelID = nil
                } else {
                    camModel.stepWorkspace.select(model: id)
                }
            },
            onToggleStepModelVisibility: { id in
                camModel.stepWorkspace.toggleVisibility(of: id)
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
            onStepModelOrientationChanged: { id, face in
                camModel.stepWorkspace.setOrientation(face, for: id)
            },
            onStepModelWidthChanged: { id, width in
                camModel.stepWorkspace.setWidth(Float(width), for: id)
            },
            onStepModelScale: { id, factor in
                camModel.stepWorkspace.scaleModel(id, factor: factor)
            },
            onDeleteStepModel: { id in
                do {
                    try projectModel.removeSTEPModel(id)
                }
                catch {
                    fileError = String(describing: error)
                }
            },
            setups: camModel.setups,
            activeSetupID: camModel.activeSetupID,
            sideFacesAvailable: hasSTEP,
            onSelectSetup: { id in
                camModel.activateSetup(id)
            },
            onAddSetup: { objectID, face in
                withAnimation(.easeOut(duration: 0.15)) {
                    let id = camModel.addSetup(face: face)
                    if let objectID {
                        camModel.setSetupObjects(id, to: [objectID])
                    }
                }
            },
            onRenameSetup: { id, name in
                camModel.renameSetup(id, to: name)
            },
            onDeleteSetup: { id in
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.deleteSetup(id)
                }
            },
            onAddCombinedSetup: { ids, face in
                withAnimation(.easeOut(duration: 0.15)) {
                    let id = camModel.addSetup(face: face)
                    camModel.setSetupObjects(id, to: ids)
                }
            },
            overriddenObjectIDs: Set(camModel.setups.first { $0.id == camModel.activeSetupID }?
                .items.filter { $0.transformOverride != nil }.map(\.objectID) ?? []),
            offersPlacementScope: camModel.setups.count > 1,
            onPlacementOverrideChanged: { id, enabled in
                camModel.setPlacementOverride(enabled, for: id)
            }
        )
    }

    private var stepModelItems: [STEPModelItem] {
        let workspace = camModel.stepWorkspace
        // One row per body of every loaded file (a file still loading has one row of its own)
        return workspace.modelEntries.map { entry -> STEPModelItem in
            guard let scene = workspace.documents[entry.sourceID], let body = entry.body else {
                return STEPModelItem(id: entry.id, name: entry.name,
                                     isVisible: workspace.documents[entry.sourceID]?.isModelVisible ?? true,
                                     position: nil, size: nil)
            }
            return STEPModelItem(id: entry.id, name: entry.name,
                                 isVisible: scene.isBodyVisible(body),
                                 position: scene.position(of: body),
                                 size: scene.content.size(of: body),
                                 orientation: scene.content.orientation(of: body),
                                 detail: entry.detail)
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
            projectModel: projectModel,
            toolpaths: camModel.toolpaths,
            selectedID: camModel.selectedToolpathID,
            setups: camModel.setups,
            activeSetupID: camModel.activeSetupID,
            onSelect: { id in
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.toggleToolpathSelection(id)
                }
            },
            onDelete: { id in
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.deleteToolpath(id)
                }
            },
            onAdd: { kind in
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.addToolpath(operation: kind)
                }
            },
            onMove: { id, index in
                camModel.moveToolpath(id, toIndexInSetup: index)
            },
            onMoveToSetup: { id, setupID in
                camModel.moveToolpath(id, toSetup: setupID)
            }
        )
    }

    /// Generate, its status and the scrub slider for the open toolpath, in a panel of its own.
    private func toolpathPreviewPanel(for toolpath: ToolpathData) -> some View {
        PanelToolpathPreview(toolpath: camModel.toolpaths.first { $0.id == toolpath.id } ?? toolpath,
                             generation: camModel.generations[toolpath.id],
                             isGenerating: camModel.generatingIDs.contains(toolpath.id),
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
                             showsFirstAndLastPassOnly: $camModel.showsFirstAndLastPassOnly)
        .id(toolpath.id)
    }

    private func toolpathSettingsPanel(for toolpath: ToolpathData) -> some View {
        PanelToolpathDetails(toolpath: binding(for: toolpath),
                             stockMaterial: camModel.stock(for: toolpath).material,
                             stockThickness: camModel.stock(for: toolpath).thickness,
                             siblingNames: Set(camModel.toolpaths.filter { $0.id != toolpath.id }.map(\.name)),
                             isPicking: camModel.pickingToolpathID == toolpath.id,
                             restSource: toolpath.operation.restSourceID.flatMap { sourceID in
                                 camModel.toolpaths.first { $0.id == sourceID }
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
                             },
                             shapeDetails: {
                                camModel.shapeDetails(for: toolpath.id)
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
