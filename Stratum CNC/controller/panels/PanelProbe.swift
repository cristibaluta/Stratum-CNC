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
                    model.sendCommand(CNC.probe.with(z: -10, feed: 50))
                } label: {
                    Label("Auto Z", systemImage: "wand.and.stars")
                }
            }
            .padding(.vertical, 4)
        }
    }
}
