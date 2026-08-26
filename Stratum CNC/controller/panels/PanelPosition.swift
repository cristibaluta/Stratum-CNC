//
//  PanelPosition.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

struct PanelPosition: View {

    @ObservedObject var connection: MachineConnection

    var body: some View {
        GroupBox("Position") {
            VStack(alignment: .leading, spacing: 8) {
                if let status = connection.status {
                    positionRow(title: "MACHINE", x: status.machinePosition.x, y: status.machinePosition.y, z: status.machinePosition.z)
                    positionRow(title: "WORK   ", x: status.workPosition.x, y: status.workPosition.y, z: status.workPosition.z)
                } else {
                    positionRow(title: "MACHINE", x: 0, y: 0, z: 0)
                    positionRow(title: "WORK   ", x: 0, y: 0, z: 0)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func positionRow(title: String, x: Double, y: Double, z: Double) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)

            Spacer()

            Text(String(format: "X%8.3f  Y%8.3f  Z%8.3f", x, y, z))
                .font(.caption)
        }
    }
}
