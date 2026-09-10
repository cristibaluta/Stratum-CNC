//
//  CanvasZoomToolbar.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 10.09.2026.
//

import SwiftUI

struct CanvasZoomToolbar: View {

    @ObservedObject var viewModel: CAMModel

    var body: some View {
        HStack(spacing: 12) {
            // Zoom Out Button
            Button(action: { zoomStep(out: true) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            
            // Logarithmic Slider centered on 1:1
            VStack(spacing: 2) {
                Slider(value: $viewModel.sliderPosition, in: 0.0...1.0) {
                    Text("Zoom Scale")
                } minimumValueLabel: {
                    Text("10%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("1000%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 180)
                
                // Tick indicator for middle point
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 1.5, height: 4)
            }
            
            // Zoom In Button
            Button(action: { zoomStep(out: false) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 16)
            
            // True to Life (1:1) Shortcut Button
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewModel.resetToTrueToLife()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "ruler")
                    Text("100% (1mm = 1mm)")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(isTrueToLife ? .blue : .gray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if let mainScreen = NSScreen.main {
                viewModel.updateTrueToLifeScale(for: mainScreen)
                viewModel.resetToTrueToLife()
            }
        }
    }
    
    private var isTrueToLife: Bool {
        abs(viewModel.canvasState.zoomScale - viewModel.trueToLifeScale) < 0.001
    }
    
    private func zoomStep(out: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            let step = out ? -0.05 : 0.05
            viewModel.sliderPosition = min(max(viewModel.sliderPosition + step, 0.0), 1.0)
        }
    }
}
