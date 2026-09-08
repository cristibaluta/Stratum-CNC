//
//  MachinesList.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.08.2026.
//

import SwiftUI

struct MachinesList: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        List(model.discovery.machines, selection: $model.selectedMachine) { machine in
            HStack {
                Circle()
                    .fill(machine.busy ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.name)
                        .font(.headline)
                    Text("\(machine.ip):\(machine.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(machine.busy ? "Busy" : "Idle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(machine)
        }
        .navigationTitle("Makera Machines")
//        .toolbar {
//            ToolbarItem {
//                Button {
//                    if model.discovery.isScanning {
//                        model.discovery.stopScanning()
//                    } else {
//                        model.discovery.startScanning()
//                    }
//                } label: {
//                    Label(
//                        model.discovery.isScanning ? "Stop" : "Scan",
//                        systemImage: model.discovery.isScanning ? "stop.circle" : "arrow.clockwise"
//                    )
//                }
//            }
//        }
        .overlay {
            if model.discovery.machines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(model.discovery.isScanning ? "Scanning for machines…" : "No machines found")
                        .font(.headline)
                    Text(model.discovery.lastError ?? "Make sure your Mac and Makera are on the same network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        }
        .onAppear { model.discovery.startScanning() }
        .onDisappear { model.discovery.stopScanning() }
    }
}
