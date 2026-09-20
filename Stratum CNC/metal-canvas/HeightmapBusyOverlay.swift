//
//  HeightmapBusyOverlay.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//


//
//  HeightmapBusyOverlay.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//

import SwiftUI

/// A spinner centered over the canvas while a heightmap carve is running on
/// its background task (see `CanvasSceneModel.isComputingHeightmap`).
///
/// Two deliberate behaviors:
///
/// - It only appears once `isBusy` has stayed true for `delay`. Small files
///   carve in a few milliseconds, and a scrub drag kicks off carves
///   continuously — a spinner that flashed on for every one of them would be
///   noise rather than information.
/// - It never takes clicks or drags (`allowsHitTesting(false)`), so orbiting
///   and panning the canvas keep working while a carve runs; the previous
///   surface stays on screen underneath until the new one lands.
struct HeightmapBusyOverlay: View {

    let isBusy: Bool

    /// How long `isBusy` must hold before the spinner shows.
    var delay: Duration = .milliseconds(150)

    @State private var isVisible = false

    var body: some View {
        ZStack {
            if isVisible {
                ProgressView()
                    .controlSize(.regular)
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: isVisible)
        // Restarted whenever `isBusy` flips. If it goes false before the
        // delay is up, this task is cancelled mid-sleep and the spinner
        // never shows.
        .task(id: isBusy) {
            guard isBusy else {
                isVisible = false
                return
            }
            try? await Task.sleep(for: delay)
            if !Task.isCancelled {
                isVisible = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        HeightmapBusyOverlay(isBusy: true, delay: .zero)
    }
    .frame(width: 300, height: 200)
}