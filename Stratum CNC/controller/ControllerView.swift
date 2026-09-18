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
        // A table-row click is a single discrete jump, not a tick in a
        // drag — `forceHeightmap: true` so the surface always matches
        // exactly where the click landed rather than possibly sitting a few
        // `heightmapScrubTickInterval` ticks stale (see
        // `CanvasSceneModel.scrubHeightmap`).
        Self.scrubTo(line: line, gCodeModel: gCodeModel, camModel: camModel, scene: model.scene, forceHeightmap: true)
    }

    fileprivate static func scrubTo(line: Int, gCodeModel: GCodeStore, camModel: CAMModel, scene: CanvasSceneModel, forceHeightmap: Bool) {
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

        // M5: the heightmap's own scrub path — throttled internally (see
        // `CanvasSceneModel.scrubHeightmap`), so it's fine to call this on
        // every tick the same way `setToolpathVisibleVertexCounts` above is.
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
                // A slider drag fires many ticks a second — `forceHeightmap:
                // false` lets `CanvasSceneModel.scrubHeightmap` throttle the
                // actual recarves. `onEditingChanged` below forces one final
                // exact recarve once the drag ends.
                ControllerView.scrubTo(line: Int(newValue.rounded()), gCodeModel: gCodeModel, camModel: camModel, scene: scene, forceHeightmap: false)
            }
        )
    }

    /// M5: forces one exact heightmap recarve at wherever the scrubber
    /// currently sits — bypasses `scrubTo`'s own throttling and its
    /// "only if `line` actually changed" guard, both of which are meant for
    /// the *stream* of ticks during a drag, not this "the drag/scroll just
    /// stopped" moment. Wired to the slider's `onEditingChanged` below, and
    /// also called directly from `onAppear`/`onChange` below for the
    /// non-scrub structural changes (new stock, new file, reassigned tool)
    /// that should also always be exact.
    private func forceHeightmapRefresh() {
        scene.scrubHeightmap(stock: camModel.selectedStockMaterial,
                             document: gCodeModel.document,
                             line: gCodeModel.scrubLine,
                             tool: gCodeModel.activeToolSpec,
                             force: true)
    }

    /// Scroll-to-scrub over the g-code slider — a trackpad swipe (or mouse
    /// wheel) anywhere over it moves the scrubber, without needing to grab
    /// the thumb. Wired up via `ScrollWheelCapture`, which claims only
    /// scroll-wheel events so dragging the actual `Slider` still works
    /// exactly as before.
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
        MetalCanvasView(objects: $scene.renderObjects,
                        renderMode: scene.renderMode,
                        xyOffset: scene.xyOffset,
                        heightmapMesh: scene.heightmapMesh)
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
                        .frame(minWidth: 100)
                    }
                    Divider().frame(height: 28)
                    VStack {
                        HeightmapQualityPickerView(cellSize: $scene.heightmapCellSize)
                            .frame(minWidth: 100)
                        XYOffsetControlView(xyOffset: $scene.xyOffset)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding()
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    Slider(value: scrubBinding, in: 0...Double(gCodeModel.document.lines.count)) { editing in
                        // M5: the drag ticks themselves are throttled (see
                        // `scrubBinding`) — this is what guarantees the
                        // surface still ends up exactly right once the
                        // person lets go, rather than possibly sitting a
                        // few ticks stale.
                        if !editing {
                            forceHeightmapRefresh()
                        }
                    }
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
                .overlay(ScrollWheelCapture(onScroll: handleScrubScroll))
            }
            .overlay(alignment: .topTrailing) {
                // M4: the wireframe/heightmap switch. `scene.renderMode`
                // alone is enough to flip `MetalRenderer.draw(in:)`'s path —
                // see `MetalCanvasView.updateNSView` — the heightmap mesh
                // itself is kept up to date independently, below, so there's
                // never a wait when this toggle moves.
                Picker("", selection: $scene.renderMode) {
                    ForEach(CanvasRenderMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.systemImage)
                            .help(mode.label)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 90)
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
            .onChange(of: scene.heightmapCellSize) { _, _ in
                // A new grid resolution needs a full recarve, same as a
                // reassigned tool — the existing mesh was built at the old
                // cell size and doesn't just resample in place.
                forceHeightmapRefresh()
            }
            .onChange(of: scene.xyOffset) { _, _ in
                // Same "just state until something recarves" story as
                // `heightmapCellSize` above — the GPU toolpath draw already
                // moves every frame off `MetalRenderer.xyOffset` regardless
                // (see `MetalCanvasView.updateNSView`), but the heightmap
                // surface has the offset baked into its carved vertices
                // (see `HeightmapGrid.carve`), so it only catches up once a
                // recarve actually runs.
                //
                // `forceHeightmapRefresh()` recarves immediately and
                // unthrottled, which is fine for a control that changes
                // value discretely (e.g. typed numeric fields). If the
                // eventual UI (M7) is a live-drag control instead, this call
                // should be swapped for the same throttle-while-dragging,
                // exact-on-release pattern `scrubBinding`/the scrub
                // `Slider`'s `onEditingChanged` use above — recarving the
                // whole grid on every drag tick would make the drag itself
                // feel laggy on a large file, same reasoning as M5's
                // `heightmapScrubTickInterval` throttle.
                forceHeightmapRefresh()
            }
    }
}
