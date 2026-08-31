//
//  PanelMachine.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

struct PanelMachine: View {

    @ObservedObject var model: ControllerStore

    var body: some View {
        GroupBox("MACHINE") {
            VStack(alignment: .leading) {
                HStack(alignment: .top, spacing: 6) {
                    Button {
                        model.sendRawCommand(model.homeCommand)
                    } label: {
                        Label("H", systemImage: "house")
                    }

                    Button {
                        model.sendRawCommand(model.unlockCommand)
                    } label: {
                        Label("Unlock", systemImage: "lock.open")
                    }

                }
                Button {
                    model.connection.requestStatus()
                } label: {
                    Label("Get Status", systemImage: "info.circle")
                }

                .buttonStyle(.bordered)
            }
        }
    }
}
