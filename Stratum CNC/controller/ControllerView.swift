//
//  ControllerView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import AppKit
import simd
import StratumLink

/// Invisible helper that keeps the tool cylinder in sync with the machine's
/// reported position. Needs its own `@ObservedObject` on `MachineConnection`
/// (the same pattern `PanelPosition` uses) because `status` is published by
/// `MachineConnection` itself, not by `ControllerModel` — `ControllerModel`
/// never forwards it, so observing `model` alone wouldn't pick up changes.
///
/// The canvas is in machine coordinates, so the tool goes where the machine
/// says it is (its machine X/Y), not where the typed anchor and offset say
/// the work origin should be: if the two disagree, the tool visibly leaves
/// the stock. The scene draws the tool at its position *plus the work
/// origin* (like the toolpath it follows), so the XY handed over is the
/// machine position minus that origin. Z stays the work Z, since the canvas
/// only maps X and Y to machine coordinates. `workOrigin` changing (another
/// anchor, an edited offset) re-sends the position for the same reason.
private struct ToolPositionSync: View {
    @ObservedObject var connection: MachineConnection
    let workOrigin: SIMD2<Float>
    let onUpdate: (SIMD3<Float>) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { sync(connection.status) }
            .onChange(of: connection.status) { _, status in sync(status) }
            .onChange(of: workOrigin) { _, _ in sync(connection.status) }
    }

    private func sync(_ status: MakeraMachineStatus?) {
        guard let status else { return }
        onUpdate(SIMD3<Float>(Float(status.machinePosition.x) - workOrigin.x,
                              Float(status.machinePosition.y) - workOrigin.y,
                              Float(status.workPosition.z)))
    }
}

struct ControllerView: View {

    @ObservedObject var model: ControllerModel
    @ObservedObject var camModel: CAMModel
    @ObservedObject var projectModel: ProjectModel
    @ObservedObject var gCodeModel: GCodeStore
    @ObservedObject var joystickStore: GameControllerStore

    /// Opens the stocks library (owned by the CAM side of the app). When nil
    /// the stock chip's icon opens the stock editor instead.
    var onOpenStocksLib: (() -> Void)? = nil

    @State private var isShowingEmptyStateRemoteFiles = false
    @State private var isShowingToolbarRemoteFiles = false

    /// Without CAM (Controller-only sessions) there is nothing to generate from.
    private var hasCAM: Bool { !projectModel.hidesCAM }

    /// Saved projects get their program from CAM only; any import happens in
    /// the Controller-only sessions.
    private var canImportGCode: Bool { projectModel.sessionKind != .project }
    /// A G-code file session keeps its import button in the nav bar, by the title.
    private var importsFromNavBar: Bool { projectModel.sessionKind == .gcodeFile }

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
        guard line != gCodeModel.scrubLine else {
            return
        }

        gCodeModel.scrubLine = line
        gCodeModel.requestedLine = line

        // Scrubbing across a tool change swaps which tool is in the spindle.
        scene.updateTool(gCodeModel.spindleToolSpec)

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
        HStack(alignment: .top, spacing: 16) {
            column1
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            column2
                .frame(width: 300)

            column3
                .frame(width: 300)
        }
        .padding(16)
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
            // G-code file sessions only: swap the file, next to its name.
            ToolbarItem(placement: .navigation) {
                if importsFromNavBar {
                    Menu {
                    Button {
                        model.isGCodeImporterPresented = true
                    } label: {
                        Label("Import from File…", systemImage: "folder")
                    }
                    Button {
                        isShowingToolbarRemoteFiles = true
                    } label: {
                        Label("Load from Machine…", systemImage: "externaldrive.badge.wifi")
                    }
                } label: {
                    Label("Import G-code", systemImage: "square.and.arrow.down")
                }
                .help("Import G-code from a file or the machine")
                .disabled(gCodeModel.document.isLoading)
                .popover(isPresented: $isShowingToolbarRemoteFiles, arrowEdge: .bottom) {
                    RemoteFilesPopover(info: model.session.info,
                                       downloader: model.session.downloader,
                                       isConnected: model.connection.isConnected) { file in
                        loadRemoteFile(file)
                    }
                }
                }
            }
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
        .sheet(isPresented: $model.isShowingRunReview) {
            MachiningRunSheet(model: model, gCodeModel: gCodeModel, camModel: camModel, connection: model.connection)
        }
        .sheet(isPresented: $model.isShowingBitChange) {
            BitChangeSheet(model: model, gCodeModel: gCodeModel, connection: model.connection)
        }
        .sheet(isPresented: $model.isShowingMachinePicker) {
            MachineConnectSheet(model: model, connection: model.connection)
        }
        .alert("Use from CAM",
               isPresented: Binding(get: { gCodeModel.camImportMessage != nil },
                                    set: { if !$0 { gCodeModel.camImportMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(gCodeModel.camImportMessage ?? "")
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
        .machineAlerts(model.alerts, onResume: model.resumeJob)
    }

    /// Downloads a program from the machine's SD card and loads it as if it
    /// had been imported from disk.
    private func loadRemoteFile(_ file: MachineFileEntry) {
        model.session.downloadGCode(path: file.path) { result in
            switch result {
            case .success(let text):
                gCodeModel.document.load(from: text, name: file.name)
                gCodeModel.selectedToolpathID = nil
                gCodeModel.requestedLine = nil
                gCodeModel.analyzedLineCount = -1
            case .failure(let error):
                gCodeModel.document.lastError = error.localizedDescription
            }
        }
    }

    /// A CAM-generated program whose source toolpaths (or stock) changed since.
    private var isProgramOutdated: Bool {
        hasCAM
            && !gCodeModel.document.isLoading
            && !gCodeModel.document.lines.isEmpty
            && gCodeModel.generatedFromCAMRevision.map { $0 != camModel.revision } == true
    }

    private func regenerateFromCAM() {
        // Generates whatever toolpaths aren't ready yet (progress shows in a popover on the
        // button that was pressed), then builds the program from them.
        gCodeModel.generateGCode(using: camModel)
    }

    private func exportGCode() {
        // A CAM-generated program carries no file name of its own; name it after the project.
        let fromCAM = gCodeModel.generatedFromCAMRevision != nil && hasCAM
        GCodeExporter.export(gCodeModel.document,
                             suggestedName: fromCAM ? projectModel.project.name : nil)
    }

    private var outdatedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("CAM toolpaths changed")
                .font(.headline)
            Text("This G-code was generated from an earlier version of your toolpaths. Refresh to regenerate it from CAM before running.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(action: regenerateFromCAM) {
                if gCodeModel.isGeneratingFromCAM {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh from CAM", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(gCodeModel.isGeneratingFromCAM)
            .popover(isPresented: $gCodeModel.isShowingCAMProgress, arrowEdge: .bottom) {
                CAMGenerationProgressView(store: gCodeModel)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }

    @ViewBuilder
    private var column1: some View {
        column1Content
            .overlay {
                if isProgramOutdated {
                    outdatedOverlay
                }
            }
    }

    @ViewBuilder
    private var column1Content: some View {
        if gCodeModel.document.isLoading {
            VStack {
                Spacer()
                loadingState
                Spacer()
            }
        } else if gCodeModel.document.lines.isEmpty && model.gcodePanelMode != .macros {
            VStack {
                Spacer()
                emptyState
                Spacer()
            }
        } else {
            CanvasSection(scene: model.scene, gCodeModel: gCodeModel,
                          camModel: camModel, connection: model.connection,
                          macros: model.macros,
                          macroDocument: model.macros.document,
                          showsMacroPreview: model.gcodePanelMode == .macros,
                          isStockVisible: stockVisibleBinding,
                          onOpenStocksLib: onOpenStocksLib,
                          onImportFile: canImportGCode && !importsFromNavBar ? { model.isGCodeImporterPresented = true } : nil,
                          session: model.session,
                          onLoadRemoteFile: loadRemoteFile)
        }
    }

    @ViewBuilder
    private var column2: some View {
        VStack(spacing: 16) {
            PanelJog(model: model,
                     joystick: joystickStore,
                     holdFeed: $model.holdJogFeed,
                     onJog: { model.jog($0) },
                     onHold: { direction, pressed in model.holdJog(direction, pressed: pressed) },
                     onStopHold: { model.stopHoldJog() })
//            .frame(height: 180)

            gcodeAndMacrosPanel
        }
//            .disabled(!model.connection.isConnected)
    }

    @ViewBuilder
    private var column3: some View {
        // Right panel with controller and console
        VStack(spacing: 16) {
            PanelPosition(connection: model.connection, model: model, scene: model.scene)

            PanelSpindle(model: model)

            GroupBox(label: Text("MDI CONSOLE")) {
                TerminalView(model: model, connection: model.connection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
//            .disabled(!model.connection.isConnected)
    }

    // MARK: - Panels

    private var gcodeAndMacrosPanel: some View {
        GroupBox {
            VStack(spacing: 6) {
                Picker("", selection: $model.gcodePanelMode) {
                    ForEach(GCodePanelMode.allCases, id: \.self) { mode in
                        Text(mode == .gcode ? "G-code" : "Macros").tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)

            GCodeViewer(model: gCodeModel,
                        uploader: model.uploader,
                        connection: model.connection,
                        macros: model.macros,
                        mode: model.gcodePanelMode,
                        onRunMacro: { model.startJob(lines: $0) },
                        highlightedLine: gCodeModel.scrubLine,
                        onLineSelected: scrubTo,
                        onPlay: {
                            if model.connection.isConnected {
                                model.isShowingRunReview = true
                            } else {
                                model.isShowingMachinePicker = true
                            }
                        },
                        onExport: exportGCode,
                        onPause: model.pauseJob,
                        onSuspend: model.suspendJob,
                        onResume: model.resumeJob,
                        onResumeFromLine: { model.resumeJob(fromLine: $0) },
                        canResumeFromLine: model.lastUploadedRemotePath != nil,
                        onChangeBit: { model.isShowingBitChange = true },
                        canChangeBit: model.connection.isConnected && model.job.progress?.isResumable == true,
                        onStop: model.stopJob)
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
                if hasCAM {
                    VStack {
                        Text("Generate G-code from CAM toolpaths")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            regenerateFromCAM()
                        } label: {
                            if gCodeModel.isGeneratingFromCAM {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Use from CAM")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(gCodeModel.isGeneratingFromCAM || gCodeModel.document.isLoading)
                        .popover(isPresented: $gCodeModel.isShowingCAMProgress, arrowEdge: .bottom) {
                            CAMGenerationProgressView(store: gCodeModel)
                        }
                    }
                }

                if canImportGCode {
                    HStack {
                        VStack {
                            Text("Load a .nc, .ngc, .gcode, .cnc, or .tap file from disk.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                model.isGCodeImporterPresented = true
                            } label: {
                                Label("Import from File…", systemImage: "folder")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(gCodeModel.document.isLoading)
                        }

                        Divider().frame(height: 40)

                        VStack {
                            Text("Load file from machine storage.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                isShowingEmptyStateRemoteFiles = true
                            } label: {
                                Label("Import from Machine…", systemImage: "externaldrive.badge.wifi")
                            }
                            .disabled(gCodeModel.document.isLoading)
                            .popover(isPresented: $isShowingEmptyStateRemoteFiles, arrowEdge: .bottom) {
                                RemoteFilesPopover(info: model.session.info,
                                                   downloader: model.session.downloader,
                                                   isConnected: model.connection.isConnected) { file in
                                    loadRemoteFile(file)
                                }
                            }
                        }
                    }
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

/// The strip under the canvas: the scrub slider normally, the running job's
/// progress bar in the same spot while a job is on the machine. Same height
/// either way so the canvas doesn't jump when a job starts or ends.
///
/// Observes the connection itself — `CanvasSection` only holds it as a plain
/// `let`, so it would never redraw on the machine's status polls (same
/// reasoning as `ToolPositionSync`).
private struct ScrubberOrJobProgress<Scrubber: View>: View {
    @ObservedObject var connection: MachineConnection
    @ViewBuilder let scrubber: () -> Scrubber

    var body: some View {
        Group {
            if let job = connection.status?.activeJob {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: job.fraction)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(verbatim: "Line \(job.currentLine)")
                        Spacer()
                        Text(verbatim: "\(job.percent)% · \(job.elapsedText)")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            } else {
                scrubber()
            }
        }
        .frame(height: 45)
    }
}

private struct CanvasSection: View {
    @ObservedObject var scene: CanvasSceneModel
    @ObservedObject var gCodeModel: GCodeStore
    @ObservedObject var camModel: CAMModel
    let connection: MachineConnection
    /// Selection of the MACROS tab. Observed so picking another macro redraws.
    @ObservedObject var macros: MacroStore
    /// The selected macro's generated G-code, parsed like any program. It is
    /// its own object (not the loaded program's), which is what lets the canvas
    /// preview a macro without ever replacing `gCodeModel.document`.
    @ObservedObject var macroDocument: NCFileDocument
    /// True while the MACROS tab is the active one. With a macro selected the
    /// canvas then shows it in place of the loaded program.
    let showsMacroPreview: Bool
    let isStockVisible: Binding<Bool>
    @Environment(\.openSettings) private var openSettings
    let onOpenStocksLib: (() -> Void)?
    /// `nil` hides the import buttons (the program comes from elsewhere).
    let onImportFile: (() -> Void)?
    let session: SL.Session
    let onLoadRemoteFile: (MachineFileEntry) -> Void
    @State private var isShowingRemoteFiles = false

    /// So the 3D viewport's background follows the app-wide day/night
    /// switch (see `ContentView`) instead of always being the renderer's
    /// hardcoded dark gray — same idea as `CAMSceneModel.backgroundColor`,
    /// just without needing a full rebuild since nothing else here is
    /// appearance-dependent.
    @Environment(\.colorScheme) private var colorScheme

    /// Background clear color for the controller's Metal viewport. Dark
    /// mode keeps the renderer's original hardcoded gray (`MetalRenderer`'s
    /// default `MTLClearColor`) so existing dark-mode users see no change;
    /// light mode is pure white.
    private var viewportClearColor: SIMD4<Float> {
        colorScheme == .dark
            ? SIMD4<Float>(0.1, 0.1, 0.1, 1)
            : SIMD4<Float>(1, 1, 1, 1)
    }

    /// Scroll movement that hasn't yet added up to a whole line. Fine
    /// scrolling moves the scrubber by well under a line per event, and
    /// rounding each event on its own would drop all of it — the scrubber
    /// would either not move at all or only in the odd big jump.
    @State private var scrubRemainder = 0.0

    /// Heightmap quality lives next to the Wireframe/Heightmap switch.
    @State private var isShowingHeightmapQuality = false

    /// Fine scrubbing: how many lines one unit of scroll moves. A precise
    /// device (trackpad, Magic Mouse) reports pixels, so this is
    /// lines-per-pixel; a notched wheel reports whole units per notch, so it
    /// is lines-per-notch. A line is the smallest step the toolpath drawing
    /// has, so this is as fine as scrubbing goes.
    private static let linesPerScrollUnit = 1.0

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

    /// Rebuilds the dotted job bounding box. Needs the segments *and* the
    /// per-line tool radii, so it runs whenever either changes — a new
    /// program, or a different tool assigned to a `T` number.
    private func refreshBoundingBox() {
        scene.updateBoundingBox(segments: gCodeModel.document.toolpathSegments,
                                toolRadii: gCodeModel.toolRadiiByLine())
    }

    /// Shows the selected macro on the canvas while the MACROS tab is active,
    /// and puts the loaded program back otherwise. Safe to call any number of
    /// times; the program is only hidden, never reloaded or re-parsed.
    private func syncMacroPreview() {
        if showsMacroPreview, macros.selectedMacro != nil {
            scene.showMacroPreview(macroDocument.toolpathSegments)
        } else {
            let counts = gCodeModel.document.toolpathVertexCounts(upTo: gCodeModel.scrubLine)
            scene.hideMacroPreview(restoringProgramVertexCounts: counts)
        }
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
        guard totalLines > 0, !scene.isMacroPreviewActive else {
            return
        }

        // A two-finger trackpad swipe reports both axes; whichever is
        // larger is almost always the one intended — preferring that over
        // always reading deltaY lets a horizontal swipe drive the scrubber
        // too, which reads naturally for a left-to-right timeline.
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY

        // A new swipe doesn't inherit the last one's leftover fraction.
        if event.phase == .began {
            scrubRemainder = 0
        }

        let step: Double
        if event.modifierFlags.contains(.shift) {
            // Shift keeps the old coarse paging, for crossing a long file
            // quickly: proportional to the swipe on a trackpad, one chunk
            // of the file per notch on a wheel.
            if event.hasPreciseScrollingDeltas {
                step = Double(delta) * Double(totalLines) * 0.002
            } else {
                let notch: Double = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
                step = notch * max(1, Double(totalLines) / 200)
            }
        } else {
            // Fine: the distance scrolled maps straight to lines, however
            // long the file is. (It used to be a fraction of the file, so a
            // small scroll of a big program jumped hundreds of lines.)
            step = Double(delta) * Self.linesPerScrollUnit
        }

        // Only whole lines can be shown; keep the fraction for the next event.
        scrubRemainder += step
        let whole = scrubRemainder.rounded(.towardZero)
        guard whole != 0 else { return }
        scrubRemainder -= whole

        let newLine = gCodeModel.scrubLine + Int(whole)
        // Like the drag binding above: a two-finger swipe can fire a burst
        // of these in quick succession, so this rides the same throttle
        // rather than forcing an exact recarve on every notch.
        ControllerView.scrubTo(line: max(0, min(totalLines, newLine)), gCodeModel: gCodeModel, camModel: camModel, scene: scene, forceHeightmap: false)
    }

    /// Where the program came from, at the left of the bar above the canvas:
    /// import from a file or the machine, and the loaded file's name.
//    private var fileControls: some View {
//        HStack(spacing: 6) {
//            if let onImportFile {
//            Button(action: onImportFile) {
//                Image(systemName: "folder")
//                    .frame(width: 22, height: 22)
//            }
//            .help("Import from file")
//            .disabled(gCodeModel.document.isLoading)
//
//            Button {
//                isShowingRemoteFiles = true
//            } label: {
//                Image(systemName: "externaldrive.badge.wifi")
//                    .frame(width: 22, height: 22)
//            }
//            .help("Load from machine")
//            .disabled(gCodeModel.document.isLoading)
//            .popover(isPresented: $isShowingRemoteFiles, arrowEdge: .bottom) {
//                RemoteFilesPopover(info: session.info,
//                                   downloader: session.downloader,
//                                   isConnected: connection.isConnected) { file in
//                    onLoadRemoteFile(file)
//                }
//            }
//            }
//
//            Text(gCodeModel.document.fileName)
//                .font(.caption.weight(.medium))
//                .foregroundStyle(gCodeModel.document.lines.isEmpty ? .secondary : .primary)
//                .lineLimit(1)
//                .truncationMode(.middle)
//                .frame(maxWidth: 180, alignment: .leading)
//                .help(gCodeModel.document.fileName)
//        }
//        .buttonStyle(.plain)
//        .fixedSize()
//    }

    var body: some View {
        VStack {
            // One slim line: the program's file (reload / import / name), then
            // the stock summary, with the program's tools pushed to the right
            // in a scrolling row. Editing happens in popovers/menus on demand.
            HStack(spacing: 10) {
                StockChip(stock: $camModel.selectedStockMaterial,
                          isStockVisible: isStockVisible,
                          onOpenLibrary: onOpenStocksLib)

                if !gCodeModel.tools.isEmpty {
                    ToolChipsView(tools: gCodeModel.tools,
                                  assignments: $gCodeModel.toolSpecAssignments,
                                  fileSpecs: gCodeModel.headerToolSpecs,
                                  activeTool: gCodeModel.activeToolNumber,
                                  alignment: .trailing)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(.regularMaterial)
            .cornerRadius(8)

            MetalCanvasView(objects: .constant(scene.visibleRenderObjects),
                            renderMode: scene.renderMode,
                            xyOffset: scene.xyOffset,
                            anchorOrigin: scene.machineLayout.activeAnchor,
                            stockColor: scene.stockColor,
                            heightmapMesh: scene.isMacroPreviewActive ? nil : scene.visibleHeightmapMesh,
                            clearColor: viewportClearColor,
                            zoomModel: scene.zoomModel)
            .cornerRadius(8)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            }
            .overlay {
                // The carve runs on a background task; the old surface
                // stays visible until the new one lands. Wireframe mode
                // never shows the surface, so it never shows the spinner.
                HeightmapBusyOverlay(isBusy: scene.renderMode == .heightmap && scene.isComputingHeightmap)
            }
            .overlay(
                ToolPositionSync(connection: connection, workOrigin: scene.workOrigin) { point in
                    scene.updateTool(gCodeModel.spindleToolSpec)
                    scene.updateToolPosition(point)
                    // A macro runs from wherever the tool is.
                    scene.setMacroOrigin(SIMD2<Float>(point.x, point.y))
                }
            )
            .overlay(alignment: .bottomLeading) {
                if scene.isMacroPreviewActive {
                    Label("Macro preview at the tool position", systemImage: "eye")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial)
                        .cornerRadius(6)
                        .padding(8)
                }
            }
            .overlay {
                CanvasCoordinateLabels(scene: scene)
            }
            .overlay(alignment: .topLeading) {
                CanvasLayersList(scene: scene) {
                    PanelStockMaterial(stock: $camModel.selectedStockMaterial,
                                       isStockVisible: isStockVisible,
                                       isCompact: true,
                                       onOpenStocksLib: nil)
                        .frame(width: 300)
                        .padding(12)
                }
                .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack {
                        Picker("", selection: $scene.renderMode) {
                            ForEach(CanvasRenderMode.allCases, id: \.self) { mode in
                                Image(systemName: mode.systemImage)
                                    .help(mode.label)
                                    .tag(mode)
                            }
                        }
                        .frame(width: 80)
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        // Carve quality only means something for the heightmap.
                        if scene.renderMode == .heightmap {
                            Button {
                                isShowingHeightmapQuality.toggle()
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                            }
                            .buttonStyle(.plain)
                            .help("Heightmap quality")
                            .popover(isPresented: $isShowingHeightmapQuality, arrowEdge: .bottom) {
                                HeightmapQualityPickerView(cellSize: $scene.heightmapCellSize)
                                    .frame(width: 190)
                                    .padding(12)
                            }
                        }

                        Divider()
                            .frame(height: 18)

                        Button {
                            SettingsTab.canvas.select()
                            openSettings()
                        } label: {
                            Image(systemName: "computermouse")
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                    .padding(2)
                    .canvasChrome()

                    CanvasZoomButton(zoomModel: scene.zoomModel)
                }
                .padding(8)
            }

            ScrubberOrJobProgress(connection: connection) {
                Slider(value: scrubBinding, in: 0...Double(max(1, gCodeModel.document.lines.count))) { editing in
                    if !editing {
                        forceHeightmapRefresh()
                    }
                }
                .disabled(gCodeModel.document.lines.isEmpty || scene.isMacroPreviewActive)
                .overlay(ScrollWheelCapture(onScroll: handleScrubScroll))
            }
        }
        .onAppear {
            // Sync once up front — `renderObjects` otherwise still
            // holds `defaultScene()`'s placeholder box, not
            // whatever material the project actually has selected.
            scene.updateStock(camModel.selectedStockMaterial)
            scene.updateToolpath(gCodeModel.document.toolpathSegments)
            refreshBoundingBox()
            gCodeModel.scrubLine = gCodeModel.document.lines.count
            scene.updateTool(gCodeModel.spindleToolSpec)
            forceHeightmapRefresh()
            syncMacroPreview()
        }
        .onChange(of: showsMacroPreview) { _, _ in
            syncMacroPreview()
        }
        .onChange(of: macros.selectedMacroID) { _, _ in
            syncMacroPreview()
        }
        .onChange(of: macroDocument.toolpathSegments) { _, _ in
            // Parameter edits regenerate the macro's G-code.
            syncMacroPreview()
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
            refreshBoundingBox()
            gCodeModel.scrubLine = gCodeModel.document.lines.count
            scene.updateTool(gCodeModel.spindleToolSpec)
            forceHeightmapRefresh()
        }
        .onChange(of: gCodeModel.toolSpecAssignments) { _, _ in
            // Assigning (or reassigning) a `T` number's tool changes
            // what the heightmap should have been carved with — e.g.
            // picking a bigger end mill widens every cut — and the tool
            // drawn on the canvas — and how far the job's bounding box
            // reaches past the toolpath.
            scene.updateTool(gCodeModel.spindleToolSpec)
            refreshBoundingBox()
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
