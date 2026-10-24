//
//  PanelCoordinate.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

/// One row of work-zero actions. Hosted inside the shared WORK SETUP box
/// in `ControllerView`, so it has no `GroupBox` of its own. "Get
/// Coordinates" is gone: it sent the same status request as the refresh
/// button in the POSITION header.
struct PanelCoordinate: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        HStack(spacing: 6) {
            PanelRowLabel("ZERO")

            Button("X") {
                model.sendRawCommand(model.zeroCommand(x: true))
            }
            .help("Set X work zero here")

            Button("Y") {
                model.sendRawCommand(model.zeroCommand(y: true))
            }
            .help("Set Y work zero here")

            Button("Z") {
                model.sendRawCommand(model.zeroCommand(z: true))
            }
            .help("Set Z work zero here")

            Spacer(minLength: 4)

            Button {
                model.sendRawCommand(model.zeroCommand(x: true, y: true, z: true))
            } label: {
                Label("XYZ", systemImage: "scope")
            }
            .buttonStyle(QuietButtonStyle(tint: .accentColor))
            .help("Set X, Y and Z work zero here")
        }
        .buttonStyle(.quiet)
    }
}
