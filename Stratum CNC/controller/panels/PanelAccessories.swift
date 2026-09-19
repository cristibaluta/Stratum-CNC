//
//  PanelAccessories.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 19.09.2026.
//

import SwiftUI

/// Vacuum and cooling accessories (Roadmap 2.2) — three power-percentage
/// controls (`CNC.internalVacuumOn`/`.spindleCoolingFanOn`/`.extendedPortOn`,
/// each a `PercentageBuilder` that clamps to 0...100) plus the auto-vacuum
/// mode toggle (`CNC.automaticVacuumOn`/`.automaticVacuumOff`, M331/M332 —
/// no percentage, it just ties the vacuum to the spindle's on/off state).
/// Like `PanelATC`, every command here was already modeled correctly; this
/// is only the missing UI.
struct PanelAccessories: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        GroupBox("VACUUM & COOLING") {
            VStack(alignment: .leading, spacing: 8) {
                PowerRow(title: "Vacuum",
                         percent: $model.vacuumPercent,
                         onCommand: { CNC.internalVacuumOn.with(percent: $0) },
                         offCommand: CNC.internalVacuumOff,
                         model: model)

                PowerRow(title: "Cooling Fan",
                         percent: $model.coolingFanPercent,
                         onCommand: { CNC.spindleCoolingFanOn.with(percent: $0) },
                         offCommand: CNC.spindleCoolingFanOff,
                         model: model)

                PowerRow(title: "Ext. Port",
                         percent: $model.extendedPortPercent,
                         onCommand: { CNC.extendedPortOn.with(percent: $0) },
                         offCommand: CNC.extendedPortOff,
                         model: model)

                Divider()

                // M331/M332 — a mode, not a momentary action, so this reads
                // as a toggle rather than the On/Off button pair above.
                HStack {
                    Text("Auto Vacuum")
                        .font(.caption)
                    Spacer()
                    Button("On") {
                        model.sendCommand(CNC.automaticVacuumOn)
                    }
                    Button("Off") {
                        model.sendCommand(CNC.automaticVacuumOff)
                    }
                }
                .help("Ties the vacuum to the spindle: on while the spindle runs, off when it stops")
            }
            .padding(.vertical, 4)
        }
    }
}

/// One "label, percent field, On, Off" row — `Vacuum`, `Cooling Fan` and
/// `Ext. Port` are identical in shape (`M8xx S<percent>` / `M8xx+1`), so
/// this avoids repeating the row three times with only the commands
/// swapped out.
private struct PowerRow: View {
    let title: String
    @Binding var percent: String
    let onCommand: (Int) -> CNCCommand
    let offCommand: CNCCommand
    @ObservedObject var model: ControllerModel

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .frame(width: 72, alignment: .leading)

            TextField("%", text: $percent)
                .textFieldStyle(.roundedBorder)
                .frame(width: 44)

            Button("On") {
                model.sendCommand(onCommand(Int(percent) ?? 100))
            }
            Button("Off") {
                model.sendCommand(offCommand)
            }
        }
    }
}
