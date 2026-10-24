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
/// Home / Unlock / Refresh live in the header — they used to be a separate
/// MACHINE panel with their own bordered buttons.
struct PanelPosition: View {

    @ObservedObject var connection: SL.Connection
    @ObservedObject var model: ControllerModel

    var body: some View {
        GroupBox {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
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
            .padding(.vertical, 2)
        } label: {
            HStack(spacing: 6) {
                Text("POSITION")
                Spacer()
                headerButton("house", help: "Home") {
                    model.sendRawCommand(model.homeCommand)
                }
                headerButton("lock.open", help: "Unlock") {
                    model.sendRawCommand(model.unlockCommand)
                }
                headerButton("arrow.clockwise", help: "Refresh status") {
                    model.connection.requestStatus()
                }
            }
        }
    }

    private func headerButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(help)
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
