//
//  PanelMachine.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

struct PanelMachine: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        GroupBox("Machine") {
            VStack(spacing: 6) {
                Button {
                    model.sendRawCommand(model.homeCommand)
                } label: {
                    Label("Home", systemImage: "house")
                }

                Button {
                    model.sendRawCommand(model.unlockCommand)
                } label: {
                    Label("Unlock", systemImage: "lock.open")
                }

                Button {
                    model.connection.requestStatus()
                } label: {
                    Label("Machine Status", systemImage: "info.circle")
                }
            }
        }
    }
}
