//
//  InteractiveMTKView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 16.09.2026.
//

import SwiftUI
import MetalKit

@MainActor
struct MetalCanvasView: NSViewRepresentable {

    // Custom MTKView subclass to capture scroll wheel events directly
    private class InteractiveMTKView: MTKView {
        var onScroll: ((NSEvent) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            onScroll?(event)
        }
    }

    @Binding var objects: [RenderObject]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = InteractiveMTKView()
        guard let renderer = MetalRenderer(metalView: mtkView) else {
            return mtkView
        }

        context.coordinator.renderer = renderer
        mtkView.delegate = renderer

        // Handle Scroll Wheel / Pinch for Zooming
        mtkView.onScroll = { [weak coordinator = context.coordinator] event in
            coordinator?.handleScroll(event)
        }

        // Mouse drag → orbit
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        mtkView.addGestureRecognizer(panGesture)

        // Trackpad pinch → zoom
        let magnification = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnification(_:)))
        mtkView.addGestureRecognizer(magnification)

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.updateGeometry(objects: objects)
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: MetalCanvasView
        var renderer: MetalRenderer?
        private var lastMousePosition: CGPoint = .zero
        private var zoom: Float = 100
        private let minZoom: Float = 0.1
        private let maxZoom: Float = 100_000

        init(_ parent: MetalCanvasView) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let camera = renderer?.camera else {
                return
            }
            let translation = gesture.translation(in: gesture.view)
            
            if NSEvent.modifierFlags.contains(.shift) {
                // Orbit Camera (Drag)
                let sensitivity: Float = 0.005
                camera.rotation.y -= Float(translation.x) * sensitivity
                camera.rotation.x = max(-.pi/2 + 0.0, min(.pi/2 - 0.0, camera.rotation.x + Float(translation.y) * sensitivity))

                // --- PRINT ROTATION VALUES ---
//                let pitchDeg = camera.rotation.x * 180 / .pi
//                let yawDeg = camera.rotation.y * 180 / .pi
//                print(String(format: "🎥 Pitch (X): %.2f rad (%.1f°) | Yaw (Y): %.2f rad (%.1f°)", camera.rotation.x, pitchDeg, camera.rotation.y, yawDeg))
            } else {
                // Pan Camera (Shift + Drag)
                let scale: Float = 0.05
                camera.target.x -= Float(translation.x) * scale
                camera.target.y -= Float(translation.y) * scale
            }
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            // Optional: Handle selection / Raycasting targeting
        }

        @objc func handleMagnification( _ gesture: NSMagnificationGestureRecognizer) {
            if gesture.state == .changed {
                let amount = Float(gesture.magnification)
                zoom *= 1 - amount
                zoom = max(minZoom, min(maxZoom, zoom))
                gesture.magnification = 0
//                requestRedraw()
//                printCamera()
            }
        }

        func handleScroll(_ event: NSEvent) {
            guard let camera = renderer?.camera else {
                return
            }
            // Adjust zoom sensitivity (scrolling deltaY)
            let zoomSensitivity: Float = 0.5
            let delta = Float(event.scrollingDeltaY) * zoomSensitivity

            // Smooth zoom exponential scaling or linear step
            if event.hasPreciseScrollingDeltas {
                camera.distance -= delta * (camera.distance * 0.02)
            } else {
                camera.distance -= delta * 2.0
            }

            // Clamp distance to prevent clipping into target or zooming out into infinity
            camera.distance = max(2.0, min(2000.0, camera.distance))
        }
    }
}
