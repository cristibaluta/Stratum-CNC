//
//  CommandPaletteView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

struct PaletteCommandView: View {

    @ObservedObject var model: ControllerStore

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    model.isShowingCommandPalette = false
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "command")

                    Text("Command Palette")
                        .font(.headline)

                    Spacer()

                    Button {
                        model.isShowingCommandPalette = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        paletteSection(title: "Favorites", commands: model.favoriteCommands)

                        paletteSection(
                            title: "Machine",
                            commands: [
                                PaletteCommand(title: "Home", rawCommand: model.homeCommand),
                                PaletteCommand(title: "Unlock", rawCommand: model.unlockCommand),
                                PaletteCommand(title: "Get status", rawCommand: model.statusCommand),
                                PaletteCommand(title: "Turn light on", command: CNC.lightOn),
                                PaletteCommand(title: "Turn light off",command: CNC.lightOff)
                            ]
                        )

                        paletteSection(title: "Spindle",
                                       commands: [
                                        PaletteCommand(title: "Spindle stop", command: CNC.spindleOff),
                                        PaletteCommand(title: "Spindle on", command: CNC.spindleOn.with(rpm: Int(model.spindleRPM) ?? 12000))
                                        // Note: firmware only implements M3/M5 — no
                                        // M4/CCW support exists to offer here.
                                       ]
                        )

                        paletteSection(
                            title: "Coordinates",
                            commands: [
                                PaletteCommand(title: "Set X zero", rawCommand: model.zeroCommand(x: true)),
                                PaletteCommand(title: "Set Y zero", rawCommand: model.zeroCommand(y: true)),
                                PaletteCommand(title: "Set Z zero", rawCommand: model.zeroCommand(z: true)),
                                PaletteCommand(title: "Set XYZ zero", rawCommand: model.zeroCommand(x: true, y: true, z: true))
                            ]
                        )

                        paletteSection(title: "Recent", commands:
                                        model.commandHistory
                            .reversed()
                            .prefix(10)
                            .map {
                                PaletteCommand(title: $0, rawCommand: $0)
                            }
                        )
                    }
                    .padding(10)
                }
            }
            .frame( width: 500, height: 500)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 30)
        }
    }

    private func paletteSection<S: Sequence>(title: String, commands: S) -> some View where S.Element == PaletteCommand {
        let commands = Array(commands)
        if commands.isEmpty {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)

                ForEach(commands) { item in
                    Button {
                        model.sendPaletteCommand(item)
                        model.isShowingCommandPalette = false
                    } label: {
                        HStack {
                            Text(item.title)

                            Spacer()

                            Text(item.rawCommand)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        )
    }
}
