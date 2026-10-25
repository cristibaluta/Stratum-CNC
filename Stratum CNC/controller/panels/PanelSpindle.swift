//
//  PanelSpindle.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import StratumLink

struct PanelSpindle: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        GroupBox {
            HStack(spacing: 6) {
                PanelRowLabel("SPINDLE")

                TextField("RPM", text: $model.spindleRPM)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)

                Text("RPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button {
                    let rpm = Int(model.spindleRPM) ?? 12000
                    model.sendCommand(CNC.spindleOn.with(rpm: rpm))
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(QuietButtonStyle(tint: .green))

                Button {
                    model.sendCommand(CNC.spindleOff)
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(QuietButtonStyle(tint: .red))
                .help("Stop spindle")
            }
            .padding(8)
        }
    }
}
