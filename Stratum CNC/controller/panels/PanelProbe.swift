//
//  PanelProbe.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

struct PanelProbe: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        GroupBox("PROBE") {
            HStack(spacing: 6) {
                Button {
                    model.sendCommand(CNC.probe.with(z: -10, feed: 50))
                } label: {
                    Label("Probe Z", systemImage: "arrow.down.to.line")
                }

                Button("Probe X") {
                    model.sendCommand(CNC.probe.with(x: 10, feed: 50))
                }

                Button("Probe Y") {
                    model.sendCommand(CNC.probe.with(y: 10, feed: 50))
                }

                Button {
                    model.autoZeroProbe()
                } label: {
                    Label("Auto Z", systemImage: "wand.and.stars")
                }
            }
            .padding(.vertical, 4)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Auto level before run", isOn: $model.levelBeforeRun)

                if model.levelBeforeRun {
                    HStack(spacing: 12) {
                        Stepper(
                            "Grid \(model.levelGridPoints)×\(model.levelGridPoints)",
                            value: $model.levelGridPoints,
                            in: 2...10
                        )
                        Stepper(
                            "Margin \(Int(model.levelMargin)) mm",
                            value: $model.levelMargin,
                            in: 0...20,
                            step: 1
                        )
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
