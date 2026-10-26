//
//  XYOffsetControlView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import SwiftUI

/// Two small numeric fields for positioning the job on the canvas, in
/// millimeters, bound to `CanvasSceneModel.xyOffset`.
///
/// (In the popover this is bound to `CanvasSceneModel.jobAreaOffset`, the box's
/// corner relative to the anchor, not the raw `xyOffset`.)
///
/// The offset moves the job area (the dotted box, see
/// `RenderObject.boundingBox`) together with the toolpath inside it, so the
/// point being edited is the box's bottom-left corner — the job origin.
/// It is edited from the Job area popover (`JobAreaSettingsView`, the gear
/// on the "Job area" row of the canvas objects list); the position panel and
/// `MachiningRunSheet` only show it, as "Job offset", and
/// `ControllerModel.startSentJob` sends it to the machine.
///
/// Numeric fields rather than a drag-pad: a typed value commits discretely
/// (on submit / focus loss), which is exactly what `CanvasSection`'s
/// `onChange(of: scene.xyOffset)` assumes when it recarves immediately and
/// unthrottled.
///
struct XYOffsetControlView: View {
    @Binding var xyOffset: SIMD2<Float>

    private var xBinding: Binding<Double> {
        Binding(
            get: { Double(xyOffset.x) },
            set: { xyOffset.x = Float($0) }
        )
    }

    private var yBinding: Binding<Double> {
        Binding(
            get: { Double(xyOffset.y) },
            set: { xyOffset.y = Float($0) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            offsetField(label: "X", value: xBinding)
            offsetField(label: "Y", value: yBinding)
            Text("mm")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .help("Job origin: position of the job area's bottom-left corner, in mm")
    }

    private func offsetField(label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.bold())
            TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
        }
    }
}

/// Popover content behind the gear on the canvas's "Job area" row: the one
/// place the job's XY offset is edited. Needs its own `@ObservedObject` on
/// the scene, since the popover is built outside any view that observes it.
struct JobAreaSettingsView: View {
    @ObservedObject var scene: CanvasSceneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JOB AREA")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            XYOffsetControlView(xyOffset: $scene.jobAreaOffset)
            Text("Position of the job area's bottom-left corner, relative to the anchor. Not stored in the G-code: the app converts it into the work origin it sends to the machine, since the CAM's own 0,0 can be anywhere in the job.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 230, alignment: .leading)
        }
        .padding(12)
    }
}

#Preview {
    XYOffsetControlView(xyOffset: .constant(SIMD2<Float>(1.5, -0.75)))
        .padding()
}
