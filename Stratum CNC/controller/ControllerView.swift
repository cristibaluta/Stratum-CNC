//
//  ControllerView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

struct ControllerView: View {

    @ObservedObject var model: ControllerModel
    @ObservedObject var gCodeModel: GCodeModel
    @ObservedObject var joystickStore: GameControllerStore

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left panel with G-code preview, slider and start buttons
            if gCodeModel.document.lines.isEmpty {
                VStack {
                    Spacer()
                    emptyState
                    Spacer()
                }
                .background(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MetalView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Right panels with g-
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    PanelCoordinate(model: model)
                    PanelProbe(model: model)
                    HStack {
                        PanelSpindle(model: model)
                        PanelMachine(model: model)
                    }
                }
                GCodeViewerView(model: gCodeModel)
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

                PanelJog(joystick: joystickStore) { x, y, z, a in
                    model.sendCommand( CNC.rapidMove.with(x: x, y: y, z: z) )
                }
                .frame(height: 200)

                TerminalView(model: model)
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


                    Picker("Machine", selection: $model.selectedMachine) {
                        ForEach(model.discovery.machines) { machine in
                            Text(machine.name).tag(machine)
                        }
                    }
                    .frame(width: 160)

                    Button {
                        model.toggleLight()
                    } label: {
                        Image(systemName: model.isLightOn ? "lightbulb.fill" : "lightbulb")
                            .foregroundStyle(model.isLightOn ? .yellow : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(model.isLightOn ? "Turn light off" : "Turn light on")
                    .disabled(!model.connection.isConnected)
                }
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
                    Text("Generate G-code from CAM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        // TODO
                    } label: {
                        Text("Use from CAM")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

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

    private var bottomControls: some View {
        HStack(spacing: 8) {
            feedOverride

            Spacer()

            if let error = model.connection.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                model.sendRawCommand("!")
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }

            Button {
                model.sendRawCommand("~")
            } label: {
                Label("Resume", systemImage: "play.fill")
            }

            Button(role: .destructive) {
                model.sendCommand(CNC.spindleOff)
                model.sendRawCommand("!")
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }

            Button(role: .destructive) {
                model.sendRawCommand("\u{18}")
            } label: {
                Label("Reset", systemImage: "xmark.octagon.fill")
            }
        }
        .disabled(!model.connection.isConnected)
    }

    private var feedOverride: some View {
        HStack(spacing: 5) {
            Text("Feed")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Feed", selection: $model.selectedFeedOverride) {
                Text("25%").tag(25)
                Text("50%").tag(50)
                Text("75%").tag(75)
                Text("100%").tag(100)
                Text("125%").tag(125)
                Text("150%").tag(150)
            }
            .labelsHidden()
            .frame(width: 80)
            .onChange(of: model.selectedFeedOverride) {
                model.sendCommand(CNC.feedOverride.with(percent: model.selectedFeedOverride))
            }
        }
    }
}
