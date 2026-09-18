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

        // With `isPaused = true` / `enableSetNeedsDisplay = false` the view
        // never renders on its own — every frame has to be requested
        // explicitly (see the gesture handlers and `drawableSizeWillChange`
        // below). `updateNSView`'s `draw()` call fires too early to show
        // anything: at that point AppKit hasn't given this view its real
        // frame yet, so the drawable is still 0×0 and the call is a no-op.
        // `layout()` is AppKit's own signal that a real size is now in
        // place, so drawing there is what actually gets the first frame
        // (and any later resize) on screen without needing a scrub/pan/zoom
        // to kick it.
        override func layout() {
            super.layout()
            draw()
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

        // Render on demand rather than continuously. The scene is static
        // almost all the time — nothing to redraw between a scrub tick, a
        // pan, or a zoom — so a 60fps timer here was burning GPU (and
        // fighting the main thread during slider drags) for no benefit.
        // `enableSetNeedsDisplay = false` alongside `isPaused = true` puts
        // the view in fully-manual mode: it draws only when something
        // explicitly calls `draw()` — which `updateNSView` below already
        // does on every geometry change, and which the gesture handlers and
        // `drawableSizeWillChange` (see `MetalRenderer`) now do too.
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = false

        context.coordinator.metalView = mtkView

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
        // Force an immediate frame rather than waiting for the view's own
        // continuous-mode redraw timer. That timer runs independently of
        // AppKit's main-thread event handling, and during an NSSlider's
        // mouse-tracking loop (dragging the scrub slider) it can lag well
        // behind — geometry updates (see `updateGeometry` above) land
        // instantly, same as the G-code table's row highlight, but without
        // this the pixels on screen don't catch up until the drag ends.
        nsView.draw()
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: MetalCanvasView
        var renderer: MetalRenderer?
        /// Weak: so the view — which owns the coordinator via AppKit's
        /// retain graph, not the other way around — can be requested to
        /// draw() from the gesture handlers below without creating a cycle.
        weak var metalView: MTKView?
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
            metalView?.draw()
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            // Optional: Handle selection / Raycasting targeting
        }

        @objc func handleMagnification( _ gesture: NSMagnificationGestureRecognizer) {
            guard let camera = renderer?.camera, let view = gesture.view else {
                return
            }
            if gesture.state == .changed {
                let amount = Float(gesture.magnification)
                let newZoom = max(minZoom, min(maxZoom, zoom * (1 - amount)))

                // Convert the cursor position to normalized device coords (-1...1,
                // origin at screen center) so the camera can keep that point fixed.
                let location = gesture.location(in: view)
                let size = view.bounds.size
                let ndc = SIMD2<Float>(
                    Float(location.x / size.width) * 2 - 1,
                    Float(location.y / size.height) * 2 - 1
                )

                camera.zoom(to: newZoom, towards: ndc)
                zoom = newZoom
                gesture.magnification = 0
                metalView?.draw()
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
            metalView?.draw()
        }
    }
}
