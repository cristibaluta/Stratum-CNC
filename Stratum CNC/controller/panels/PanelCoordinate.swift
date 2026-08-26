//
//  PanelCoordinate.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

struct PanelCoordinate: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        GroupBox("Work Coordinates") {
            VStack(spacing: 6) {
                HStack {
                    Text("Zero")
                        .font(.caption)
                    Button("X") {
                        model.sendRawCommand(model.zeroCommand(x: true))
                    }
                    Button("Y") {
                        model.sendRawCommand(model.zeroCommand(y: true))
                    }
                    Button("Z") {
                        model.sendRawCommand(model.zeroCommand(z: true))
                    }
                    Spacer()
                }

                HStack {
                    Button {
                        model.sendRawCommand(model.zeroCommand(x: true, y: true, z: true))
                    } label: {
                        Label("Set XYZ Zero", systemImage: "scope")
                    }

                    Button {
                        model.connection.requestStatus()
                    } label: {
                        Label("Get Coordinates", systemImage: "location")
                    }
                }
            }
        }
    }
}
