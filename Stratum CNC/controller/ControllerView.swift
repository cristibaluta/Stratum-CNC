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

    private var stockVisibleBinding: Binding<Bool> {
        Binding(
            get: { projectModel.projectData.isStockVisible ?? true },
            set: { newValue in
                projectModel.projectData.isStockVisible = newValue
                camModel.canvasState.isStockVisible = newValue
            }
        )
    }

    /// Drives the scrub slider. `Slider` needs a `Double`, but the scrub
    /// position is really a 1-based G-code line, so this rounds to the
    /// nearest line on every drag tick. Setting `gCodeModel.requestedLine`
    /// is what makes `GCodeTableView` select and scroll to that row (it's
    /// edge-triggered on the value changing, which fits a slider that fires
    /// on every tick); re-rendering the canvas reuses `ControllerModel`'s
    /// existing role-based replace (`updateToolpath`) with just the segments
    /// up to that line, instead of the full file.
    private var scrubBinding: Binding<Double> {
        Binding(
            get: { Double(gCodeModel.scrubLine) },
            set: { newValue in
                let line = Int(newValue.rounded())
                guard line != gCodeModel.scrubLine else { return }

                gCodeModel.scrubLine = line
                gCodeModel.requestedLine = line

                let prefix = gCodeModel.document.toolpathSegments(upTo: line)
                model.updateToolpath(Array(prefix))

                // Move the cutter marker to wherever the scrubbed path ends,
                // so the canvas reads as "the tool is here" rather than just
                // a partially-drawn line. If a machine is connected,
                // `ToolPositionSync` will overwrite this on the next status
                // update — scrubbing is meant for reviewing an offline file,
                // not for tracking a job that's actually running.
                if let last = prefix.last {
                    model.updateToolPosition(last.end)
                }
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left panel with G-code preview, slider and start buttons
            if gCodeModel.document.lines.isEmpty {
                VStack {
                    Spacer()
                    emptyState
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MetalCanvasView(objects: $model.renderObjects)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .padding(.trailing, -16)
                    .overlay(
                        ToolPositionSync(connection: model.connection) { point in
                            model.updateToolPosition(point)
                        }
                    )
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
                        model.updateStock(camModel.selectedStockMaterial)
                        model.updateToolpath(gCodeModel.document.toolpathSegments)
                        gCodeModel.scrubLine = gCodeModel.document.lines.count
                    }
                    .onChange(of: camModel.selectedStockMaterial) { _, newStock in
                        model.updateStock(newStock)
                    }
                    .onChange(of: gCodeModel.document.toolpathSegments) { _, newSegments in
                        // A freshly (re)parsed file replaces the whole preview
                        // and parks the scrubber at the end, so what's drawn
                        // always matches where the slider sits.
                        model.updateToolpath(newSegments)
                        gCodeModel.scrubLine = gCodeModel.document.lines.count
                    }
            }

            // Right panels with g-
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    MaterialPanelView(stock: $camModel.selectedStockMaterial,
                                      isStockVisible: stockVisibleBinding)
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
                    GCodeViewer(model: gCodeModel, highlightedLine: gCodeModel.scrubLine)
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
