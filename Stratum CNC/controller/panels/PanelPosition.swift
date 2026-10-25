//
//  PanelPosition.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import StratumLink

/// Work and machine position as an aligned X/Y/Z/A table. Work is the one
/// you read while jogging, so it is the larger row; machine is secondary.
/// Home / Unlock / Status sit in a labelled row below the table — they used
/// to be a separate MACHINE panel with their own bordered buttons.
struct PanelPosition: View {

    @ObservedObject var connection: SL.Connection
    @ObservedObject var model: ControllerModel

    var body: some View {
        GroupBox {//}("POSITION") {
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .gridColumnAlignment(.leading)
                        ForEach(["X", "Y", "Z", "A"], id: \.self) { axis in
                            Text(axis)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let status = connection.status {
                        positionRow(title: "WORK",
                                    values: [status.workPosition.x, status.workPosition.y, status.workPosition.z, 0],
                                    prominent: true)
                        positionRow(title: "MACHINE",
                                    values: [status.machinePosition.x, status.machinePosition.y, status.machinePosition.z, 0],
                                    prominent: false)
                    } else {
                        positionRow(title: "WORK", values: [0, 0, 0, 0], prominent: true)
                        positionRow(title: "MACHINE", values: [0, 0, 0, 0], prominent: false)
                    }
                }

                // Labelled, so it's clear what each one does.
                HStack(spacing: 8) {
                    Button {
                        model.sendRawCommand(model.homeCommand)
                    } label: {
                        Label("Home", systemImage: "house")
                    }
                    .help("Run the homing cycle")

                    Button {
                        model.sendRawCommand(model.unlockCommand)
                    } label: {
                        Label("Unlock", systemImage: "lock.open")
                    }
                    .help("Clear the alarm lock so the machine can move")

                    Button {
                        model.connection.requestStatus()
                    } label: {
                        Label("Status", systemImage: "info.circle")
                    }
                    .help("Ask the machine for its current status")

                    Spacer(minLength: 0)
                }
                .buttonStyle(.quiet)
            }
            .padding(8)
        }
    }

    private func positionRow(title: String, values: [Double], prominent: Bool) -> some View {
        GridRow {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)

            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(String(format: "%.3f", value))
                    .font(.system(size: prominent ? 12 : 10.5,
                                  weight: prominent ? .medium : .regular,
                                  design: .monospaced))
                    .foregroundStyle(prominent && index < 3 ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}
