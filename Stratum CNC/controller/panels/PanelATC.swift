//
//  PanelATC.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 19.09.2026.
//

import SwiftUI

/// Manual controls for the automatic tool changer (Roadmap 2.1). Every
/// command here — `CNC.toolChange`, `.automaticToolChangerHome`,
/// `.tightenSpindleCollet`, `.loosenSpindleCollet`, `.calibrateTool`,
/// `.automaticToolChangeStatus` — was already fully modeled in
/// `CNCCommand`/`CNC+Shortcuts` with correct string formatting; this panel
/// is only the "~55 of ~65 modeled commands have zero UI" gap Phase 2 is
/// about, not new command-building logic.
struct PanelATC: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        GroupBox("ATC") {
            VStack(alignment: .leading, spacing: 8) {
                // M6 — swap the tool in the spindle for the numbered one.
                HStack {
                    Text("Tool")
                        .font(.caption)

                    TextField("Tool", text: $model.atcToolNumber)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 44)

                    Button {
                        model.sendCommand(CNC.toolChange.with(tool: Int(model.atcToolNumber) ?? 0))
                    } label: {
                        Label("Change", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Divider()

                // M490 / M490.1 / M490.2 — collet homing and open/close.
                // Homing runs automatically before tighten/loosen if the
                // ATC needs it, per `CNCCommand.automaticToolChangerHome`'s
                // doc comment, so the Home button here is for recovering a
                // confused ATC by hand, not a required first step.
                HStack(spacing: 6) {
                    Button {
                        model.sendCommand(CNC.automaticToolChangerHome)
                    } label: {
                        Label("Home", systemImage: "house")
                    }
                    Button {
                        model.sendCommand(CNC.tightenSpindleCollet)
                    } label: {
                        Label("Tighten", systemImage: "lock")
                    }
                    Button {
                        model.sendCommand(CNC.loosenSpindleCollet)
                    } label: {
                        Label("Loosen", systemImage: "lock.open")
                    }
                }

                Divider()

                // M491 — recalibrate TLO for whatever tool is currently in
                // the spindle.
                Button {
                    model.sendCommand(CNC.calibrateTool)
                } label: {
                    Label("Calibrate Tool", systemImage: "scope")
                }

                ATCStatusOverrideView(model: model)
            }
            .padding(.vertical, 4)
        }
    }
}

/// M497.1–.7 — manually declares which step of the ATC sequence the
/// firmware should consider itself in (drop tool / pick tool / calibrate /
/// margin / z-probe / autolevel / done — see `ATCStatus`). This isn't part
/// of normal tool-change use (that's the M6 button above, which the
/// firmware sequences through these steps on its own) — it exists to
/// unstick or manually step through an ATC cycle that stalled mid-sequence,
/// so it's tucked behind a disclosure rather than sitting next to Change.
private struct ATCStatusOverrideView: View {
    @ObservedObject var model: ControllerModel
    @State private var isExpanded = false

    /// Two-column grid keeps this compact enough for the 300pt side panel
    /// this lives in — 8 buttons in one row would overflow it.
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        DisclosureGroup("Manual ATC State (M497)", isExpanded: $isExpanded) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(ATCStatus.allCases, id: \.self) { status in
                    Button(status.label) {
                        model.sendCommand(CNC.automaticToolChangeStatus.with(status: status))
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 4)
        }
        .font(.caption)
    }
}

private extension ATCStatus {
    /// Short button label — `CNCCommand.ATCStatus`'s own doc comment is the
    /// source for what each subcode means; this just renders it.
    var label: String {
        switch self {
            case .none: "None"
            case .dropTool: "Drop Tool"
            case .pickTool: "Pick Tool"
            case .calibrate: "Calibrate"
            case .margin: "Margin"
            case .zProbe: "Z-Probe"
            case .autoLevel: "Autolevel"
            case .done: "Done"
        }
    }
}
