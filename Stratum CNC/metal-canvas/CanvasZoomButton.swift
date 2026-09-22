//
//  CanvasZoomButton.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 22.09.2026.
//

import SwiftUI

/// "Back to true-to-life size" button for a `MetalCanvasView` — see
/// `CanvasZoomModel`. Doubles as a zoom readout: whenever the canvas isn't
/// (close enough to) 100%, the current level is shown next to the button, so
/// no separate label is needed elsewhere in the overlay.
struct CanvasZoomButton: View {

    @ObservedObject var zoomModel: CanvasZoomModel

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                zoomModel.resetToTrueToLife()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ruler")
                Text("100%")
                if !zoomModel.isTrueToLife {
                    Text("(\(Int(zoomModel.percent.rounded()))%)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(zoomModel.isTrueToLife ? .blue : .gray)
        .help("Zoom to true-to-life size (1 mm on screen = 1 mm on the workpiece)")
    }
}

#Preview {
    VStack(spacing: 12) {
        CanvasZoomButton(zoomModel: {
            let model = CanvasZoomModel()
            return model
        }())
        CanvasZoomButton(zoomModel: {
            let model = CanvasZoomModel()
            model.updatePercent(64)
            return model
        }())
    }
    .padding()
}
