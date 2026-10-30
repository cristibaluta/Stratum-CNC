//
//  MachinesSection.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 30.10.2026.
//
//  The machines found on the network, with their status, in the left column of the projects
//  page. Rows look like `QuickActionRow`s; clicking one opens the controller.
//

import SwiftUI
import StratumLink

struct MachinesSection: View {

    @ObservedObject var discovery: SL.Discovery
    var onOpenController: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if discovery.machines.isEmpty {
                emptyState
            } else {
                ForEach(discovery.machines) { machine in
                    MachineStatusRow(machine: machine, action: onOpenController)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            if discovery.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            Text(discovery.isScanning ? "Looking for machines…" : "No machines found")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .help(discovery.lastError ?? "Make sure your Mac and the machine are on the same network.")
    }
}

/// One machine: a status dot, its name and its state at the right.
private struct MachineStatusRow: View {

    let machine: SL.MakeraMachine
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .frame(width: 24, height: 24)

                Text(machine.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(machine.isMock ? "Simulated machine, no hardware required" : "\(machine.ip):\(machine.port)\nOpen the controller")
        .onHover { isHovered = $0 }
    }

    private var statusColor: Color {
        if machine.isMock {
            return .secondary
        }
        return machine.busy ? .orange : .green
    }

    private var statusText: String {
        if machine.isMock {
            return "Simulated"
        }
        return machine.busy ? "Busy" : "Idle"
    }
}
