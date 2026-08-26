//
//  MetalView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//

import SwiftUI
import MetalKit
import simd

struct MetalView: NSViewRepresentable {

    func makeCoordinator() -> Renderer {
        Renderer()
    }

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported")
        }

        let view = MTKView()
        view.device = device

        let renderer = context.coordinator
        renderer.attach(to: view)

        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.035, green: 0.035, blue: 0.05, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        // Mouse drag → orbit
        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Renderer.handlePan(_:)))
        view.addGestureRecognizer(pan)

        // Trackpad pinch → zoom
        let magnification = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Renderer.handleMagnification(_:)))
        view.addGestureRecognizer(magnification)

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
    }
}
