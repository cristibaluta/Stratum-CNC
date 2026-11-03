//
//  PanelProbe.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import StratumLink

/// One row of probe actions. Hosted inside `PanelPosition`, under the zero
/// row — probing is the other way of setting the work origin. The auto-level options (grid, margin) are set once and
/// rarely touched, so they sit behind the slider button instead of taking
/// two rows of controls; the button is tinted while auto-level is on.
struct PanelProbe: View {

    @ObservedObject var model: ControllerModel
    @State private var isShowingLevelOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            quickRow
            guidedRow
        }
        .buttonStyle(.quiet)
    }

    /// The guided dialog for corners and centers. Its own row: the quick row
    /// above already fills the panel's width.
    private var guidedRow: some View {
        HStack(spacing: 6) {
            PanelRowLabel("")

            Button {
                model.isShowingProbe = true
            } label: {
                Label("3D Probe…", systemImage: "cube.transparent")
            }
            .buttonStyle(QuietButtonStyle(tint: .accentColor))
            .help("Find a corner or the center of the stock with the 3D probe")

            Spacer(minLength: 4)
        }
    }

    private var quickRow: some View {
        HStack(spacing: 6) {
            PanelRowLabel("PROBE")

            Button("Z") {
                model.sendCommand(CNC.probe.with(z: -10, feed: 50))
            }
            .help("Probe Z (10 mm down)")

            Button("X") {
                model.sendCommand(CNC.probe.with(x: 10, feed: 50))
            }
            .help("Probe X (10 mm)")

            Button("Y") {
                model.sendCommand(CNC.probe.with(y: 10, feed: 50))
            }
            .help("Probe Y (10 mm)")

            Button {
                model.autoZeroProbe()
            } label: {
                Label("Auto Z", systemImage: "wand.and.stars")
            }
            .buttonStyle(QuietButtonStyle(tint: .accentColor))

            Spacer(minLength: 4)

            Button {
                isShowingLevelOptions.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(QuietButtonStyle(tint: model.levelBeforeRun ? .accentColor : .secondary))
            .help(model.levelBeforeRun ? "Auto level before run: on" : "Auto level before run: off")
            .popover(isPresented: $isShowingLevelOptions, arrowEdge: .bottom) {
                levelOptions
            }
        }
    }

    private var levelOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Auto level before run", isOn: $model.levelBeforeRun)

            if model.levelBeforeRun {
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
        }
        .font(.caption)
        .padding(12)
        .frame(width: 220)
    }
}
