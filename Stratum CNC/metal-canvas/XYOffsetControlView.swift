//
//  XYOffsetControlView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import SwiftUI

/// Two small numeric fields for nudging the job's XY origin on the canvas,
/// in millimeters. Meant to sit alongside `HeightmapQualityPickerView` in
/// the canvas top overlay, next to `CanvasSceneModel.xyOffset`, the value
/// it edits.
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
        VStack(alignment: .leading, spacing: 2) {
            Text("XY Offset")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                offsetField(label: "X", value: xBinding)
                offsetField(label: "Y", value: yBinding)
            }
        }
    }

    private func offsetField(label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
        }
    }
}

#Preview {
    XYOffsetControlView(xyOffset: .constant(SIMD2<Float>(1.5, -0.75)))
        .padding()
}
