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
/// The offset moves the job's dotted bounding box (see
/// `RenderObject.boundingBox`) together with the toolpath inside it, so the
/// point being edited is the box's bottom-left corner — the job origin.
/// `MachiningRunSheet` shows the same value as "X Offset / Y Offset" and
/// `ControllerModel.uploadJob` sends it to the machine.
///
/// Numeric fields rather than a drag-pad: a typed value commits discretely
/// (on submit / focus loss), which is exactly what `CanvasSection`'s
/// `onChange(of: scene.xyOffset)` assumes when it recarves immediately and
/// unthrottled.
///
/// It no longer floats over the canvas; `PanelOffset` hosts it as a row of
/// the WORK SETUP panel, next to zero and probe — it is the same idea (where
/// the job's origin sits), just typed instead of touched off.
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
        .help("Job origin: position of the bounding box's bottom-left corner, in mm")
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

/// The WORK SETUP row for the job's XY offset. Needs its own
/// `@ObservedObject` on the scene: `ControllerView` only observes
/// `ControllerModel`, which doesn't forward the scene's changes.
struct PanelOffset: View {
    @ObservedObject var scene: CanvasSceneModel

    var body: some View {
        HStack(spacing: 6) {
            PanelRowLabel("OFFSET")
            XYOffsetControlView(xyOffset: $scene.xyOffset)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    XYOffsetControlView(xyOffset: .constant(SIMD2<Float>(1.5, -0.75)))
        .padding()
}
