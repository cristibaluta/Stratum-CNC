//
//  PanelProbe.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import StratumLink

/// One row of probe actions. Hosted inside `PanelPosition`, under the zero
/// row — probing is the other way of setting the work origin. The single button
/// opens the guided 3D Probe dialog, where what to probe (Z surface, corner,
/// center) is chosen. Auto-level lives in the run review sheet.
struct PanelProbe: View {

    @ObservedObject var model: ControllerModel

    var body: some View {
        HStack(spacing: 6) {
            PanelRowLabel("PROBE")

            Button {
                model.isShowingProbe = true
            } label: {
                Label("Probe…", systemImage: "dot.viewfinder")
            }
            .buttonStyle(QuietButtonStyle(tint: .accentColor))
            .help("Find the Z surface, a corner or the center of the stock with the 3D probe")

            Spacer(minLength: 4)
        }
        .buttonStyle(.quiet)
    }
}
