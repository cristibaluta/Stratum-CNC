//
//  PanelPosition.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import StratumLink

/// Everything about *where things are*, in one panel, top to bottom:
///
///     [Home] [Unlock when in alarm]                  [refresh]
///              X      Y      Z      A
///     MACHINE  …      …      …      …     the fixed frame, zero at the home switches
///     WORK     …      …      …      …     what the G-code is written in — the row you read while jogging
///     JOB      …      …                   the job offset: where the job's origin sits (mm), read-only
///     ───────
///     ZERO     X Y Z                XYZ   set the work origin here
///     PROBE    Z X Y  Auto Z        ⚙     find the surface, then set the origin
///
/// The first two rows are live readouts of the machine; JOB OFFSET shows a setting
/// for the job (`CanvasSceneModel.xyOffset`, which Fusion's X/Y Offset header
/// also fills in) and doesn't change while jogging. It is not editable here:
/// change it from the gear on the canvas's "Job area" row. ZERO and PROBE are the
/// two ways of setting the work origin, so they sit under the work row
/// instead of in a box of their own. This panel replaces the old POSITION
/// and WORK SETUP boxes.
struct PanelPosition: View {

    @ObservedObject var connection: SL.Connection
    @ObservedObject var model: ControllerModel
    /// The offset lives on the canvas scene. `ControllerView` only observes
    /// `ControllerModel`, which doesn't forward the scene's changes, so the
    /// panel observes it itself (same reason `PanelOffset` did).
    @ObservedObject var scene: CanvasSceneModel

    /// GRBL-style state strings ("Alarm", "Idle", "Run", …). Unlock only
    /// matters in an alarm, so it only shows then.
    private var isAlarm: Bool {
        connection.status?.state.lowercased().hasPrefix("alarm") == true
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    model.connection.requestStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Ask the machine for its current position and status")
                .padding(.bottom, -16)

                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .gridColumnAlignment(.leading)
                        ForEach(["X", "Y", "Z", "A"], id: \.self) { axis in
                            Text(axis)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let status = connection.status {
                        positionRow(title: "MCS",
                                    values: [status.machinePosition.x, status.machinePosition.y, status.machinePosition.z, 0],
                                    prominent: false)
                        positionRow(title: "WCS",
                                    values: [status.workPosition.x, status.workPosition.y, status.workPosition.z, 0],
                                    prominent: true)
                    } else {
                        positionRow(title: "MCS", values: [0, 0, 0, 0], prominent: false)
                        positionRow(title: "WCS", values: [0, 0, 0, 0], prominent: true)
                    }

                }

                Divider()

                offsetRow
                PanelCoordinate(model: model)
                PanelProbe(model: model)
            }
            .padding(8)
        }
    }

    // MARK: - Rows

    private func positionRow(title: String, values: [Double], prominent: Bool) -> some View {
        GridRow {
            rowTitle(title)

            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(String(format: "%.3f", value))
                    .font(.system(size: prominent ? 12 : 10.5,
                                  weight: prominent ? .medium : .regular,
                                  design: .monospaced))
                    .foregroundStyle(prominent && index < 3 ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// The job offset, read-only, shown as text (same style as the MCS row).
    /// XY only, like the canvas offset it is — Z comes from touch-off or
    /// probing. Edited in the Job area popover on the canvas.
    private var offsetRow: some View {
        HStack(spacing: 8) {
            rowTitle("JOB OFFSET")
            offsetValue(scene.xyOffset.x, axis: "X")
            offsetValue(scene.xyOffset.y, axis: "Y")
            Spacer()
        }
        .help("Job offset: where the job's origin sits, in mm. Change it from the gear on the canvas's Job area row.")
    }

    private func offsetValue(_ value: Float, axis: String) -> some View {
        HStack(spacing: 3) {
            Text(axis)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(String(format: "%.3f", value))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func rowTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .gridColumnAlignment(.leading)
    }
}
