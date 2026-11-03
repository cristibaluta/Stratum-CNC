//
//  ProbeJogPad.swift
//  Stratum CNC
//
//  A small step-jog pad for the probing dialog. The dialog is modal, so the
//  main `PanelJog` can't be clicked while it is open. This is deliberately not
//  another `PanelJog`: that one reads the game controller's single event
//  stream, and two readers would split the button presses between them. A
//  game controller enabled in the main panel keeps working under the dialog.
//

import SwiftUI
import StratumLink

struct ProbeJogPad: View {

    @ObservedObject var model: ControllerModel
    @ObservedObject var connection: SL.Connection

    @State private var step = 1.0
    private let steps = [0.1, 1.0, 10.0]

    var body: some View {
        GroupBox {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            jogButton("arrow.up", help: "Y+ (away from you)", y: 1)
                            Color.clear.frame(width: 1, height: 1)
                        }
                        GridRow {
                            jogButton("arrow.left", help: "X−", x: -1)
                            Color.clear.frame(width: 1, height: 1)
                            jogButton("arrow.right", help: "X+", x: 1)
                        }
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            jogButton("arrow.down", help: "Y− (toward you)", y: -1)
                            Color.clear.frame(width: 1, height: 1)
                        }
                    }

                    Divider()
                        .frame(height: 90)

                    VStack(spacing: 4) {
                        jogButton("arrow.up.to.line", help: "Z up", z: 1)
                        Text("Z")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        jogButton("arrow.down.to.line", help: "Z down", z: -1)
                    }
                }

                Picker("Step", selection: $step) {
                    ForEach(steps, id: \.self) { value in
                        Text("\(ProbeFlow.mm(value)) mm").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if !connection.isConnected {
                    Text("Connect to a machine to jog.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
        }
        .disabled(!connection.isConnected)
    }

    private func jogButton(_ symbol: String, help: String, x: Double = 0, y: Double = 0, z: Double = 0) -> some View {
        Button {
            model.jog(.relative(x: x == 0 ? nil : x * step,
                                y: y == 0 ? nil : y * step,
                                z: z == 0 ? nil : z * step,
                                a: nil))
        } label: {
            Image(systemName: symbol)
                .frame(width: 36, height: 26)
        }
        .buttonStyle(.quiet)
        .help(help)
    }
}
