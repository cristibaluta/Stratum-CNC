//
//  XYOffsetControlView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import SwiftUI

/// Two small numeric fields for positioning the job on the canvas, in
/// millimeters. Sits in the canvas's top-right button stack, next to
/// `CanvasSceneModel.xyOffset`, the value it edits.
///
/// The offset moves the job's dotted bounding box (see
/// `RenderObject.boundingBox`) together with the toolpath inside it, so the
/// point being edited is the box's bottom-left corner — the job origin.
/// `MachiningRunSheet` shows the same value as "X Offset / Y Offset" and
/// `ControllerModel.uploadJob` sends it to the machine.
///
/// This is the "numeric fields" option from the roadmap rather than a
/// drag-pad: a typed value commits discretely (on submit / focus loss),
/// which is exactly what `CanvasSection`'s `onChange(of: scene.xyOffset)`
/// assumes when it recarves immediately and unthrottled — a drag-pad would
/// instead need to throttle while dragging and force an exact recarve on
/// release, the same way the scrub slider does.
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
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .help("Job origin: position of the bounding box's bottom-left corner, in mm")
            offsetField(label: "X", value: xBinding)
            offsetField(label: "Y", value: yBinding)
        }
        .padding(.horizontal, 8)
        .padding(2)
        .frame(height: 28)
        .background(.gray)
        .cornerRadius(8)
    }

    private func offsetField(label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.bold())
            TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
        }
    }
}

#Preview {
    XYOffsetControlView(xyOffset: .constant(SIMD2<Float>(1.5, -0.75)))
        .padding()
}
