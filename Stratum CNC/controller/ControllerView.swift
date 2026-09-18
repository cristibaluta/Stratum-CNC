//
//  ControllerView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import simd

/// Invisible helper that keeps the tool cylinder in sync with the machine's
/// reported position. Needs its own `@ObservedObject` on `MachineConnection`
/// (the same pattern `PanelPosition` uses) because `status` is published by
/// `MachineConnection` itself, not by `ControllerModel` — `ControllerModel`
/// never forwards it, so observing `model` alone wouldn't pick up changes.
private struct ToolPositionSync: View {
    @ObservedObject var connection: MachineConnection
    let onUpdate: (SIMD3<Float>) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { sync(connection.status) }
            .onChange(of: connection.status) { _, status in sync(status) }
    }

    private func sync(_ status: MakeraMachineStatus?) {
        guard let status else { return }
        onUpdate(SIMD3<Float>(Float(status.workPosition.x),
                              Float(status.workPosition.y),
                              Float(status.workPosition.z)))
    }
}

struct ControllerView: View {

    @ObservedObject var model: ControllerModel
    @ObservedObject var camModel: CAMModel
    @ObservedObject var projectModel: ProjectModel
    @ObservedObject var gCodeModel: GCodeStore
    @ObservedObject var joystickStore: GameControllerStore

    @State private var isShowingCanvasControlsSettings = false

    private var stockVisibleBinding: Binding<Bool> {
        Binding(
            get: { projectModel.projectData.isStockVisible ?? true },
            set: { newValue in
                projectModel.projectData.isStockVisible = newValue
                camModel.canvasState.isStockVisible = newValue
            }
        )
    }

    /// Parks the scrubber — and everything that follows it, the G-code
    /// table's selection and the Metal canvas — on `line`. Shared by the
    /// canvas section's slider and by manually selecting a row in
    /// `GCodeTableView` (wired up as `onLineSelected` where `GCodeViewer` is
    /// built, below), so the two stay interchangeable: dragging the slider
    /// moves the table's selection, and clicking a row moves the slider.
    /// Also called from `CanvasSection`'s own slider — kept as one free
    /// function (rather than duplicated in both places) since both need the
    /// exact same guard/update sequence.
    ///
    /// Deliberately does *not* call `CanvasSceneModel.updateToolpath` here —
    /// that re-tessellates its segments into a brand-new `RenderObject`
    /// (new `id`), which forces `MetalRenderer` to rebuild the GPU buffer
    /// from scratch. On a large file, doing that on every tick of a drag
    /// scaled with however far into the file you'd scrubbed, so dragging
    /// further in got progressively slower. The full-length toolpath is
    /// already uploaded once (`onAppear`/`onChange` in `CanvasSection` call
    /// `updateToolpath` with the *whole* file); scrubbing only needs to
    /// change how much of that existing buffer is visible, via
    /// `setToolpathVisibleVertexCounts` — an O(1) lookup plus an in-place
    /// field mutation, no matter how far into the file the slider sits.
    private func scrubTo(line: Int) {
        Self.scrubTo(line: line, gCodeModel: gCodeModel, scene: model.scene)
    }

    fileprivate static func scrubTo(line: Int, gCodeModel: GCodeStore, scene: CanvasSceneModel) {
        guard line != gCodeModel.scrubLine else { return }

        gCodeModel.scrubLine = line
        gCodeModel.requestedLine = line

        let counts = gCodeModel.document.toolpathVertexCounts(upTo: line)
        scene.setToolpathVisibleVertexCounts(rapid: counts.rapid, cutting: counts.cutting)

        // Move the cutter marker to wherever the scrubbed path ends, so the
        // canvas reads as "the tool is here" rather than just a partially-
        // drawn line. If a machine is connected, `ToolPositionSync` will
        // overwrite this on the next status update — scrubbing is meant for
        // reviewing an offline file, not for tracking a job that's actually
        // running.
        // `.last` on the slice is O(1); this doesn't materialize the prefix
        // into an `Array` the way the old code did.
        if let last = gCodeModel.document.toolpathSegments(upTo: line).last {
            scene.updateToolPosition(last.end)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left panel with G-code preview, slider and start buttons
            if gCodeModel.document.isLoading {
                VStack {
                    Spacer()
                    loadingState
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if gCodeModel.document.lines.isEmpty {
                VStack {
                    Spacer()
                    emptyState
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CanvasSection(scene: model.scene, gCodeModel: gCodeModel,
                              camModel: camModel, connection: model.connection,
                              isStockVisible: stockVisibleBinding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .padding(.trailing, -16)
            }

            // Right panels with g-
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    PanelCoordinate(model: model)
                    PanelProbe(model: model)
                }
                .frame(maxWidth: .infinity)

                GroupBox(label:
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            model.connection.requestStatus()
                        } label: {
                            Text("G-CODE")
                        }
                        .buttonStyle(.borderless)
                        Divider().frame(height: 14)// The divider likes to expand if not constrained
                        Button {
                            model.connection.requestStatus()
                        } label: {
                            Text("MACROS")
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                    .padding(.top, 4)
                ) {
                    GCodeViewer(model: gCodeModel, highlightedLine: gCodeModel.scrubLine, onLineSelected: scrubTo)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            }
            .frame(width: 300)
            .padding(16)
            .padding(.trailing, -16)
//            .disabled(!model.connection.isConnected)

            // Right panel with controller and console
            VStack(spacing: 16) {
                PanelPosition(connection: model.connection)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top)  {
                    PanelSpindle(model: model)
                    PanelMachine(model: model)
                }
                .frame(maxWidth: .infinity)

                PanelJog(joystick: joystickStore) { x, y, z, a in
                    model.sendCommand( CNC.rapidMove.with(x: x, y: y, z: z) )
                }
                .frame(height: 200)

                GroupBox(label: Text("MDI CONSOLE")) {
                    TerminalView(model: model)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 300)
            .padding(16)
//            .disabled(!model.connection.isConnected)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let machine = model.selectedMachine {
                model.connection.connect(to: machine)
            }
        }
        .onDisappear {
            model.connection.disconnect()
        }
        .onChange(of: model.selectedMachine) {
            model.connection.disconnect()
            if let machine = model.selectedMachine {
                model.connection.connect(to: machine)
            }
        }
        .overlay {
            if model.isShowingCommandPalette {
                PaletteCommandView(model: model)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Machine", selection: $model.selectedMachine) {
                    ForEach(model.discovery.machines) { machine in
                        Text(machine.name).tag(machine)
                    }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                HStack {
//                    if let machine = model.selectedMachine {
//                        Text(machine.name)
//                            .font(.title2)
//                            .bold()
//
//                        Text("\(machine.ip):\(machine.port)")
//                            .font(.caption)
//                            .foregroundStyle(.secondary)
//                    } else {
//                        Text("Machine not selected")
//                    }

                    if let status = model.connection.status {
                        statusSummary(status)
                    }

                    connectionIndicator

                    Divider()

                    Button {
                        if let machine = model.selectedMachine {
                            model.connection.connect(to: machine)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reconnect")
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.toggleLight()
                } label: {
                    Image(systemName: model.isLightOn ? "lightbulb.max.fill" : "lightbulb.slash")
                        .foregroundStyle(model.isLightOn ? .yellow : .secondary)
                }
                .help(model.isLightOn ? "Turn light off" : "Turn light on")
                .disabled(!model.connection.isConnected)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCanvasControlsSettings = true
                } label: {
                    Image(systemName: "computermouse")
                }
                .help("Canvas Mouse Controls")
            }
        }
        .sheet(isPresented: $isShowingCanvasControlsSettings) {
            NavigationStack {
                CanvasControlsSettingsView()
            }
        }
        .fileImporter(isPresented: $model.isGCodeImporterPresented,
                      allowedContentTypes: gCodeModel.allowedContentTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
                case .success(let urls):
                    if let url = urls.first {
                        gCodeModel.document.load(from: url)
                        gCodeModel.selectedToolpathID = nil
                        gCodeModel.requestedLine = nil
                        gCodeModel.analyzedLineCount = -1
                    }
                case .failure(let error):
                    gCodeModel.document.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading G-code file…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No G-code file loaded")
                .font(.headline)

            HStack(spacing: 16) {
                VStack {
                    Text("Generate G-code from CAM toolpaths")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        // TODO: use toolpaths not paths
//                        if let file = camModel.files.first {
//                            gCodeModel.generateGCode(svgPaths: file.paths)
//                        }
                    } label: {
                        Text("Use from CAM")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider().frame(height: 40)

                VStack {
                    Text("Load a .nc, .ngc, .gcode, .cnc, or .tap file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.isGCodeImporterPresented = true
                    } label: {
                        Label("Load G-code File…", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gCodeModel.document.isLoading)
                }
            }
        }
    }

    private var connectionIndicator: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.connection.isConnected ? .green : .red)
                .frame(width: 9, height: 9)

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.connection.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)

                if let proto = model.connection.wireProtocol {
                    Text(proto.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusSummary(_ status: MakeraMachineStatus) -> some View {
        HStack(spacing: 3) {
            Text(status.state)
                .font(.caption.bold())

            Text(String(format: "X %.3f  Y %.3f  Z %.3f", status.workPosition.x, status.workPosition.y, status.workPosition.z))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

/// Everything scrub-related, in one view that owns its own `@ObservedObject`
/// subscriptions to `CanvasSceneModel` and `GCodeStore`. Splitting this out of
/// `ControllerView` means a scrub tick only re-runs *this* view's `body` —
/// not `ControllerView`'s, which would otherwise reconstruct every sibling
/// panel (material/coordinate/probe on the left, position/spindle/machine/
/// jog/terminal on the right) on every slider tick for no reason.
private struct CanvasSection: View {
    @ObservedObject var scene: CanvasSceneModel
    @ObservedObject var gCodeModel: GCodeStore
    @ObservedObject var camModel: CAMModel
    let connection: MachineConnection
    let isStockVisible: Binding<Bool>

    private var scrubBinding: Binding<Double> {
        Binding(
            get: { Double(gCodeModel.scrubLine) },
            set: { newValue in
                ControllerView.scrubTo(line: Int(newValue.rounded()), gCodeModel: gCodeModel, scene: scene)
            }
        )
    }

    var body: some View {
        MetalCanvasView(objects: $scene.renderObjects)
            .overlay(
                ToolPositionSync(connection: connection) { point in
                    scene.updateToolPosition(point)
                }
            )
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: 12) {
                    MaterialPanelView(stock: $camModel.selectedStockMaterial,
                                      isStockVisible: isStockVisible)

                    if !gCodeModel.tools.isEmpty {
                        Divider().frame(height: 28)
                        ToolsPickerView(tools: gCodeModel.tools,
                                        assignments: $gCodeModel.toolSpecAssignments)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding()
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    Slider(value: scrubBinding, in: 0...Double(gCodeModel.document.lines.count))
                        .frame(minWidth: 160)
                    Text("Line \(gCodeModel.scrubLine) / \(gCodeModel.document.lines.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 90, alignment: .trailing)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding()
            }
            .onAppear {
                // Sync once up front — `renderObjects` otherwise still
                // holds `defaultScene()`'s placeholder box, not
                // whatever material the project actually has selected.
                scene.updateStock(camModel.selectedStockMaterial)
                scene.updateToolpath(gCodeModel.document.toolpathSegments)
                gCodeModel.scrubLine = gCodeModel.document.lines.count
            }
            .onChange(of: camModel.selectedStockMaterial) { _, newStock in
                scene.updateStock(newStock)
            }
            .onChange(of: gCodeModel.document.toolpathSegments) { _, newSegments in
                // A freshly (re)parsed file replaces the whole preview
                // and parks the scrubber at the end, so what's drawn
                // always matches where the slider sits.
                scene.updateToolpath(newSegments)
                gCodeModel.scrubLine = gCodeModel.document.lines.count
            }
    }
}
