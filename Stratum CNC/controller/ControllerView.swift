//
//  ControllerView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import AppKit
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

    private func scrubTo(line: Int) {
        Self.scrubTo(line: line, gCodeModel: gCodeModel, camModel: camModel, scene: model.scene, forceHeightmap: true)
    }

    fileprivate static func scrubTo(line: Int, gCodeModel: GCodeStore, camModel: CAMModel, scene: CanvasSceneModel, forceHeightmap: Bool) {
        guard line != gCodeModel.scrubLine else { return }

        gCodeModel.scrubLine = line
        gCodeModel.requestedLine = line

        let counts = gCodeModel.document.toolpathVertexCounts(upTo: line)
        scene.setToolpathVisibleVertexCounts(rapid: counts.rapid, cutting: counts.cutting)

        // Move the cutter marker to wherever the scrubbed path ends
        if let last = gCodeModel.document.toolpathSegments(upTo: line).last {
            scene.updateToolPosition(last.end)
        }

        scene.scrubHeightmap(stock: camModel.selectedStockMaterial,
                             document: gCodeModel.document,
                             line: line,
                             tool: gCodeModel.activeToolSpec,
                             force: forceHeightmap)
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
                              isStockVisible: stockVisibleBinding,
                              isShowingCanvasControlsSettings: $isShowingCanvasControlsSettings)
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

                PanelJog(joystick: joystickStore,
                         holdFeed: $model.holdJogFeed,
                         onJog: { model.jog($0) },
                         onHold: { direction, pressed in model.holdJog(direction, pressed: pressed) },
                         onStopHold: { model.stopHoldJog() })
                .frame(height: 235)

                GroupBox(label: Text("MDI CONSOLE")) {
                    TerminalView(model: model, connection: model.connection)
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
            model.stopHoldJog()
            model.connection.disconnect()
        }
        .onChange(of: model.selectedMachine) {
            model.stopHoldJog()
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

private struct CanvasSection: View {
    @ObservedObject var scene: CanvasSceneModel
    @ObservedObject var gCodeModel: GCodeStore
    @ObservedObject var camModel: CAMModel
    let connection: MachineConnection
    let isStockVisible: Binding<Bool>
    @Binding var isShowingCanvasControlsSettings: Bool

    private var scrubBinding: Binding<Double> {
        Binding(
            get: { Double(gCodeModel.scrubLine) },
            set: { newValue in
                // A slider drag fires many ticks a second — `forceHeightmap:
                // false` lets `CanvasSceneModel.scrubHeightmap` throttle the
                // actual recarves. `onEditingChanged` below forces one final
                // exact recarve once the drag ends.
                ControllerView.scrubTo(line: Int(newValue.rounded()), gCodeModel: gCodeModel, camModel: camModel, scene: scene, forceHeightmap: false)
            }
        )
    }

    private func forceHeightmapRefresh() {
        scene.scrubHeightmap(stock: camModel.selectedStockMaterial,
                             document: gCodeModel.document,
                             line: gCodeModel.scrubLine,
                             tool: gCodeModel.activeToolSpec,
                             force: true)
    }

    private func handleScrubScroll(_ event: NSEvent) {
        let totalLines = gCodeModel.document.lines.count
        guard totalLines > 0 else {
            return
        }

        // A two-finger trackpad swipe reports both axes; whichever is
        // larger is almost always the one intended — preferring that over
        // always reading deltaY lets a horizontal swipe drive the scrubber
        // too, which reads naturally for a left-to-right timeline.
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY

        let step: Double
        if event.hasPreciseScrollingDeltas {
            // Trackpad: proportional to how far you swiped rather than a
            // fixed amount, so a longer swipe moves further through the file.
            step = Double(delta) * Double(totalLines) * 0.002
        } else {
            // Mouse wheel: one deliberate chunk of the file per notch — this
            // should feel like paging through, not like a fine nudge.
            let notch: Double = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
            step = notch * max(1, Double(totalLines) / 200)
        }

        let newLine = Int((Double(gCodeModel.scrubLine) + step).rounded())
        // Like the drag binding above: a two-finger swipe can fire a burst
        // of these in quick succession, so this rides the same throttle
        // rather than forcing an exact recarve on every notch.
        ControllerView.scrubTo(line: max(0, min(totalLines, newLine)), gCodeModel: gCodeModel, camModel: camModel, scene: scene, forceHeightmap: false)
    }

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                MaterialPanelView(stock: $camModel.selectedStockMaterial, isStockVisible: isStockVisible, isCompact: true)

                if !gCodeModel.tools.isEmpty {
                    Divider()
                    ToolsPickerView(tools: gCodeModel.tools,
                                    assignments: $gCodeModel.toolSpecAssignments,
                                    fileSpecs: gCodeModel.headerToolSpecs)
                        .frame(width: 100)
                }
                Divider()
                VStack {
                    HeightmapQualityPickerView(cellSize: $scene.heightmapCellSize)
                        .frame(minWidth: 100)
                    XYOffsetControlView(xyOffset: $scene.xyOffset)
                }
            }
            .padding(8)
            .frame(height: 100)
            .background(.regularMaterial)
            .cornerRadius(8)
            .padding()

            MetalCanvasView(objects: $scene.renderObjects,
                            renderMode: scene.renderMode,
                            xyOffset: scene.xyOffset,
                            stockColor: scene.stockColor,
                            heightmapMesh: scene.heightmapMesh)
            .cornerRadius(8)
            .overlay(
                ToolPositionSync(connection: connection) { point in
                    scene.updateToolPosition(point)
                }
            )
            .overlay(alignment: .topTrailing) {
                HStack {
                    Picker("", selection: $scene.renderMode) {
                        ForEach(CanvasRenderMode.allCases, id: \.self) { mode in
                            Image(systemName: mode.systemImage)
                                .tint(.white)
                                .help(mode.label)
                                .tag(mode)
                        }
                    }
                    .frame(width: 80)
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Button {
                        isShowingCanvasControlsSettings = true
                    } label: {
                        Image(systemName: "computermouse")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
                .padding(2)
                .background(.white)
                .cornerRadius(8)
                .padding(8)
            }

            Slider(value: scrubBinding, in: 0...Double(gCodeModel.document.lines.count)) { editing in
                if !editing {
                    forceHeightmapRefresh()
                }
            }
            .frame(height: 45)
            .overlay(ScrollWheelCapture(onScroll: handleScrubScroll))
        }
        .onAppear {
            // Sync once up front — `renderObjects` otherwise still
            // holds `defaultScene()`'s placeholder box, not
            // whatever material the project actually has selected.
            scene.updateStock(camModel.selectedStockMaterial)
            scene.updateToolpath(gCodeModel.document.toolpathSegments)
            gCodeModel.scrubLine = gCodeModel.document.lines.count
            forceHeightmapRefresh()
        }
        .onChange(of: camModel.selectedStockMaterial) { _, newStock in
            scene.updateStock(newStock)
            forceHeightmapRefresh()
        }
        .onChange(of: gCodeModel.document.toolpathSegments) { _, newSegments in
            // A freshly (re)parsed file replaces the whole preview
            // and parks the scrubber at the end, so what's drawn
            // always matches where the slider sits.
            scene.updateToolpath(newSegments)
            gCodeModel.scrubLine = gCodeModel.document.lines.count
            forceHeightmapRefresh()
        }
        .onChange(of: gCodeModel.toolSpecAssignments) { _, _ in
            // Assigning (or reassigning) a `T` number's tool changes
            // what the heightmap should have been carved with — e.g.
            // picking a bigger end mill widens every cut.
            forceHeightmapRefresh()
        }
        .onChange(of: scene.renderMode) { _, mode in
            // The heightmap is only carved while it's the visible mode
            // (see `CanvasSceneModel.updateHeightmap`), so switching to
            // it needs one exact carve at the current scrub position.
            if mode == .heightmap {
                forceHeightmapRefresh()
            }
        }
        .onChange(of: scene.heightmapCellSize) { _, _ in
            // A new grid resolution needs a full recarve, same as a
            // reassigned tool — the existing mesh was built at the old
            // cell size and doesn't just resample in place.
            forceHeightmapRefresh()
        }
        .onChange(of: gCodeModel.document.loadedHeader) { _, header in
            // A file that declares its own XY offset (Fusion's
            // "X Offset / Y Offset") sets the canvas offset on load,
            // replacing whatever was nudged for the previous file.
            // Files whose header says nothing about it leave the
            // current value alone.
            if let offset = header?.xyOffset {
                scene.xyOffset = offset
            }
        }
        .onChange(of: scene.xyOffset) { _, _ in
            forceHeightmapRefresh()
        }
    }
}
