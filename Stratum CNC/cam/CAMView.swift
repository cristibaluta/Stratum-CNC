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
    - PanelSetupDetails                         <- the selected setup's object and stock (CAMModel.activeStock) + the shared isStockVisible flag
    - ToolpathListView                         <- left, under the objects panel: select / show-hide / delete toolpaths
    - ToolpathCellView                         <- right, under the material panel: only while a toolpath is selected
*/
struct CAMView: View {

    @ObservedObject var appModel: AppModel
    @ObservedObject var camModel: CAMModel
    @ObservedObject var projectModel: ProjectModel
    @State private var fileError: String?
    /// Bumped by the fit button to frame the whole scene again.
    @State private var fitRequest = 0
    /// The setup whose details are open (its pencil or "Edit…"); nil when none is.
    @State private var editingSetupID: UUID?
    /// The object whose properties are open (its pencil or "Edit…"); nil when none is.
    @State private var editingObjectID: UUID?
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
        .onAppear {
            camModel.ensureDefaultSetups()
        }
        // Selecting an object (list or canvas) ends the active setup
        .onChange(of: !camModel.canvasState.selectedObjectIDs.isEmpty || camModel.stepWorkspace.selectedModelID != nil) { _, hasSelection in
            if hasSelection, camModel.isSetupSelected {
                camModel.isSetupSelected = false
            }
        }
        // Clicking empty canvas deselects: the properties panel closes with it
        .onChange(of: camModel.canvasState.selectedObjectIDs.isEmpty && camModel.stepWorkspace.selectedModelID == nil) { _, isEmpty in
            if isEmpty {
                editingObjectID = nil
            }
        }
        .onChange(of: camModel.projectObjects.map(\.id)) { _, _ in
            camModel.ensureDefaultSetups()
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
                           skipsFlip: { camModel.skipsFlipAnimation },
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
                        setupsPanel
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
    }

    /// The selected setup's details (its object, stock and fixtures) or the selected object's placement,
    /// and the selected toolpath's settings under it.
    private var rightPanels: some View {
        VStack(alignment: .trailing, spacing: 16) {
            // One selection at a time: a setup shows its object, stock and fixtures, an object its face up, position, size
            if let setup = camModel.setups.first(where: { $0.id == editingSetupID }), selectedToolpath == nil {
                let projectStock = camModel.projectStock(for: setup)
                PanelSetupDetails(setup: setup,
                                  objects: setupObjects,
                                  stocks: camModel.stocks,
                                  setupCounts: camModel.setupCountsByStock,
                                  projectStock: projectStock,
                                  // The stock is the project's, shared by the setups cut from it
                                  stock: Binding(get: { camModel.projectStock(for: setup).stock },
                                                 set: { camModel.setStock(projectStock.id, to: $0) }),
                                  isStockVisible: stockVisibleBinding,
                                  stocksStore: appModel.stocksStore,
                                  warning: camModel.activeStockWarning,
                                  onSetObjects: { ids in
                                      // Choosing the objects by hand makes it a plain setup, no longer a group's
                                      camModel.setSetupGroup(setup.id, to: nil)
                                      camModel.setSetupObjects(setup.id, to: ids)
                                  },
                                  onSelectStock: { id in
                                      camModel.assignStock(id, to: setup.id)
                                  },
                                  onNewStock: {
                                      camModel.addStock(projectStock.stock, fixtures: projectStock.fixtures, for: setup.id)
                                  },
                                  onPickLibraryStock: { stock in
                                      camModel.useLibraryStock(stock, for: setup.id)
                                  },
                                  onRemoveUnusedStocks: {
                                      camModel.removeUnusedStocks()
                                  },
                                  onSetUsesFixtures: { uses in
                                      camModel.setSetupUsesFixtures(setup.id, uses)
                                  },
                                  onFixtureChanged: { fixtureID, diameter, offset in
                                      camModel.setAlignmentPins(stockID: projectStock.id, fixtureID: fixtureID,
                                                                diameter: diameter, offset: offset)
                                  },
                                  onRemoveFixtures: {
                                      camModel.removeFixtures(from: projectStock.id)
                                  },
                                  onDone: {
                                       editingSetupID = nil
                                   },
                                  onRename: { name in
                                      camModel.renameSetup(setup.id, to: name)
                                  })
                .frame(width: 260)
            } else if editingObjectID != nil, selectedToolpath == nil {
                objectPropertiesPanel
            }
            // Only while a toolpath is selected in the list
            if let toolpath = selectedToolpath {
                toolpathSettingsPanel(for: toolpath)
                .transition(.opacity)
                .frame(width: 320)
            }
        }
        .padding(16)
    }

    /// The imported objects a setup can cut: everything except the fixtures.
    private var setupObjects: [PanelSetups.ObjectItem] {
        camModel.canvasState.objects.filter { !$0.isParametric }.map { PanelSetups.ObjectItem(id: $0.id, name: $0.name) }
            + stepModelItems.map { PanelSetups.ObjectItem(id: $0.id, name: $0.name) }
    }

    /// The objects, their setups and the STEP models, in the list on the left.
    private var inspectorPanel: some View {
        // The list shows the canvas's selection (several objects can be selected to combine them)
        let realSelection = camModel.canvasState.selectedObjectIDs
        return PanelObjectsInspector(
            elements: camModel.canvasState.objects,
            selectedIDs: realSelection,
            onSelectionChanged: { id, extend in
                editingObjectID = nil
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
            onAddNew: {
                camModel.showingFilePicker = true
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
            selectedStepModelID: camModel.canvasState.selectedObjectIDs.isEmpty ? camModel.stepWorkspace.selectedModelID : nil,
            onSelectStepModel: { id in
                editingObjectID = nil
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
            onDeleteStepModel: { id in
                do {
                    try projectModel.removeSTEPModel(id)
                }
                catch {
                    fileError = String(describing: error)
                }
            },
            focusedObjectID: camModel.focusedObjectID,
            onSelectObject: { id in
                editingObjectID = nil
                let focusChanges = id != camModel.focusedObjectID
                if focusChanges {
                    camModel.skipsFlipAnimation = true
                    DispatchQueue.main.async { camModel.skipsFlipAnimation = false }
                }
                camModel.focusObject(id, keepingActiveSetup: false)
                if camModel.canvasState.object(withID: id) != nil {
                    camModel.stepWorkspace.selectedModelID = nil
                    camModel.canvasState.selectObject(id)
                } else {
                    camModel.canvasState.clearSelection()
                    camModel.stepWorkspace.select(model: id)
                }
            },
            onEditObject: { id in
                editingSetupID = nil
                let focusChanges = id != camModel.focusedObjectID
                if focusChanges {
                    camModel.skipsFlipAnimation = true
                    DispatchQueue.main.async { camModel.skipsFlipAnimation = false }
                }
                camModel.focusObject(id, keepingActiveSetup: false)
                if camModel.canvasState.object(withID: id) != nil {
                    camModel.stepWorkspace.selectedModelID = nil
                    camModel.canvasState.selectObject(id)
                } else {
                    camModel.canvasState.clearSelection()
                    camModel.stepWorkspace.select(model: id)
                }
                editingObjectID = id
            },
            isSetupSelected: camModel.isSetupSelected,
            groups: camModel.objectGroups.map { group in
                let names = group.memberIDs.compactMap { camModel.projectObject(withID: $0)?.name }
                return GroupItem(id: group.id, name: group.name, memberCount: names.count,
                                 memberNames: names, memberIDs: group.memberIDs)
            },
            onCreateGroup: {
                var members = camModel.canvasState.objects
                    .filter { !$0.isParametric && camModel.canvasState.selectedObjectIDs.contains($0.id) }
                    .map(\.id)
                // A selected STEP body counts when no 2D object is selected
                if members.isEmpty, let step = camModel.stepWorkspace.selectedModelID {
                    members = [step]
                }
                camModel.createGroup(memberIDs: members)
            },
            onAddToGroup: { ids, groupID in
                camModel.addToGroup(groupID, objectIDs: ids)
            },
            onRemoveFromGroup: { ids, groupID in
                camModel.removeFromGroup(groupID, objectIDs: ids)
            },
            onSelectGroup: { id in
                editingObjectID = nil
                guard let group = camModel.objectGroups.first(where: { $0.id == id }) else {
                    return
                }
                let shapes = group.memberIDs.filter { camModel.canvasState.object(withID: $0) != nil }
                camModel.stepWorkspace.selectedModelID = nil
                camModel.canvasState.clearSelection()
                for (index, member) in shapes.enumerated() {
                    if index == 0 {
                        camModel.canvasState.selectObject(member)
                    } else {
                        camModel.canvasState.toggleObjectSelection(member)
                    }
                }
            },
            onRenameGroup: { id, name in
                camModel.renameGroup(id, to: name)
            },
            onDeleteGroup: { id in
                camModel.deleteGroup(id)
            },
            onAddSetup: { objectID, face, axis in
                editingObjectID = nil
                withAnimation(.easeOut(duration: 0.15)) {
                    let id = camModel.addSetup(face: face, axis: axis, inheritingFixtures: true)
                    camModel.setSetupObjects(id, to: [objectID])
                    camModel.isSetupSelected = true
                    editingSetupID = id
                }
            },
            sideFacesAvailable: hasSTEP
        )
    }

    /// The selected object's face up, position and size, in a panel of its own on the right.
    private var objectPropertiesPanel: some View {
        // The panel shows the focused object, or the group when several are selected
        let realSelection = camModel.canvasState.selectedObjectIDs
        let focus = camModel.focusedObjectID
        let focusIs2D = focus.map { camModel.canvasState.object(withID: $0) != nil } ?? false
        var propertyIDs: Set<UUID> = []
        if realSelection.count > 1 {
            propertyIDs = realSelection
        } else if let focus, focusIs2D {
            propertyIDs = [focus]
        }
        let focusedStepID = focusIs2D ? nil : focus
        return PanelObjectProperties(
            elements: camModel.canvasState.objects,
            selectedIDs: propertyIDs,
            selectionBounds: camModel.canvasState.selectionBounds,
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
            stepModels: stepModelItems,
            selectedStepModelID: focusedStepID,
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
            overriddenObjectIDs: Set(camModel.setups.first { $0.id == camModel.activeSetupID }?
                .items.filter { $0.positionOverride != nil }.map(\.objectID) ?? []),
            offersPlacementScope: camModel.setups.count > 1,
            onPlacementOverrideChanged: { id, enabled in
                camModel.setPlacementOverride(enabled, for: id)
            },
            onDone: {
                editingObjectID = nil
            }
        )
        .frame(width: 320)
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

    /// The setups, in a panel of their own under the objects. Choosing, adding and removing them is here.
    private var setupsPanel: some View {
        PanelSetups(
            // The objects that can have setups: everything except the alignment pins
            objects: setupObjects,
            setups: camModel.setups,
            activeSetupID: camModel.activeSetupID,
            isSetupSelected: camModel.isSetupSelected,
            toolpathCounts: Dictionary(camModel.toolpaths.compactMap { toolpath in
                toolpath.setupID.map { ($0, 1) }
            }, uniquingKeysWith: +),
            toolpaths: camModel.toolpaths,
            selectedToolpathID: camModel.selectedToolpathID,
            projectModel: projectModel,
            onAddToolpath: { setupID, kind in
                withAnimation(.easeOut(duration: 0.15)) {
                    // The toolpath goes to the active setup: the one whose + was used becomes it
                    camModel.activateSetup(setupID)
                    camModel.addToolpath(operation: kind)
                }
            },
            onSelectToolpath: { id in
                editingObjectID = nil
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.toggleToolpathSelection(id)
                }
            },
            onDeleteToolpath: { id in
                withAnimation(.easeOut(duration: 0.15)) {
                    camModel.deleteToolpath(id)
                }
            },
            onMoveToolpath: { id, index in
                camModel.moveToolpath(id, toIndexInSetup: index)
            },
            onMoveToolpathToSetup: { id, setupID in
                camModel.moveToolpath(id, toSetup: setupID)
            },
            sideFacesAvailable: hasSTEP,
            groups: camModel.objectGroups.map { PanelSetups.ObjectItem(id: $0.id, name: $0.name) },
            combinableSelection: camModel.canvasState.objects
                .filter { !$0.isParametric && camModel.canvasState.selectedObjectIDs.contains($0.id) }
                .map(\.id),
            onSelectSetup: { id in
                // A setup is selected instead of an object: no object keeps its handles
                // A setup of another object than the focused one replaces the whole view of the
                // canvas and the panels: it appears at once, not animated
                let owner = camModel.setups.first { $0.id == id }?.items.first?.objectID
                let changesObject = owner != nil && owner != camModel.focusedObjectID
                let select = {
                    editingSetupID = nil
                    editingObjectID = nil
                    camModel.canvasState.clearSelection()
                    camModel.stepWorkspace.selectedModelID = nil
                    camModel.activateSetup(id)
                    camModel.isSetupSelected = true
                }
                if changesObject {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        camModel.withoutFlipAnimation(select)
                    }
                } else {
                    select()
                }
            },
            onEditSetup: { id in
                editingObjectID = nil
                camModel.canvasState.clearSelection()
                camModel.stepWorkspace.selectedModelID = nil
                camModel.activateSetup(id)
                camModel.isSetupSelected = true
                editingSetupID = id
            },
            onAddSetup: { objectID, face, axis in
                withAnimation(.easeOut(duration: 0.15)) {
                    // A new setup is cut from the active setup's stock, and keeps its fixtures
                    let id = camModel.addSetup(face: face, axis: axis, inheritingFixtures: true)
                    if let objectID {
                        camModel.setSetupObjects(id, to: [objectID])
                    }
                    camModel.isSetupSelected = true
                    editingSetupID = id
                }
            },
            onAddGroupSetup: { groupID, face, axis in
                withAnimation(.easeOut(duration: 0.15)) {
                    if let id = camModel.addGroupSetup(groupID, face: face, axis: axis) {
                        camModel.isSetupSelected = true
                        editingSetupID = id
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
            onAddCombinedSetup: { ids, face, axis in
                withAnimation(.easeOut(duration: 0.15)) {
                    let id = camModel.addSetup(face: face, axis: axis, inheritingFixtures: true)
                    camModel.setSetupObjects(id, to: ids)
                    camModel.isSetupSelected = true
                    editingSetupID = id
                }
            },
            onAddSetupLike: { sourceID, face, axis in
                guard let source = camModel.setups.first(where: { $0.id == sourceID }) else {
                    return
                }
                withAnimation(.easeOut(duration: 0.15)) {
                    let id = camModel.addSetup(face: face, axis: axis, inheritingFixtures: true)
                    // The same objects (positions are the new setup's own); a group's setup stays the group's
                    camModel.setSetupObjects(id, to: source.items.map(\.objectID))
                    camModel.setSetupGroup(id, to: source.groupID)
                    camModel.isSetupSelected = true
                    editingSetupID = id
                }
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
