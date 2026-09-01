//
//  PanelSpindle.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

struct PanelSpindle: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        GroupBox("SPINDLE") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("RPM")
                        .font(.caption)

                    TextField(
                        "RPM",
                        text: $model.spindleRPM
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }

                HStack(spacing: 6) {
                    Button {
                        let rpm = Int(model.spindleRPM) ?? 12000
                        model.sendCommand(CNC.spindleOn.with(rpm: rpm))
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }

                    Button(action: {
                        model.sendCommand(CNC.spindleOff)
                    }) {
                        Image(systemName: "stop.fill")
                    }
                }
                // Note: the firmware only implements M3 (on) / M5 (off) —
                // there's no M4/CCW support, so no separate CW/CCW toggle exists.
            }
            .padding(.vertical, 4)
        }
    }
}
