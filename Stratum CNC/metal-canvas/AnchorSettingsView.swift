//
//  AnchorSettingsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.10.2026.
//


//
//  AnchorSettingsView.swift
//  Stratum CNC
//
//  Popover behind the gear on the objects list's Anchor row: pick which
//  anchor the work is clamped against, and see/adjust where each one is in
//  machine coordinates. See `MachineLayout`.
//

import SwiftUI

struct AnchorSettingsView: View {

    @ObservedObject var scene: CanvasSceneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ANCHOR")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Anchor", selection: $scene.machineLayout.selected) {
                ForEach(AnchorChoice.allCases) { choice in
                    Text("\(choice.label) · \(choice.placement)").tag(choice)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Divider()

            Text("Position of the bracket's inside corner, in machine coordinates (mm)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            positionRow(for: .anchor1,
                        x: $scene.machineLayout.anchor1.x,
                        y: $scene.machineLayout.anchor1.y)
            positionRow(for: .anchor2,
                        x: $scene.machineLayout.anchor2.x,
                        y: $scene.machineLayout.anchor2.y)

            HStack {
                Spacer()
                Button("Reset positions") {
                    scene.machineLayout.resetAnchors()
                }
                .controlSize(.small)
            }
        }
        .frame(width: 280)
        .padding(12)
    }

    private func positionRow(for choice: AnchorChoice, x: Binding<Float>, y: Binding<Float>) -> some View {
        let isActive = scene.machineLayout.selected == choice
        return HStack(spacing: 6) {
            Text(choice.label)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .frame(width: 56, alignment: .leading)

            field("X", value: x)
            field("Y", value: y)
        }
    }

    private func field(_ label: String, value: Binding<Float>) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.caption.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
        }
    }
}