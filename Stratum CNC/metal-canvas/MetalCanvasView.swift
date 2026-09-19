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

    /// M4: which draw path `MetalRenderer.draw(in:)` takes, forwarded
    /// straight through in `updateNSView`. A plain `let`, not a `@Binding` —
    /// nothing downstream of the renderer ever needs to change it back, it
    /// only ever flows from `CanvasSceneModel.renderMode`.
    var renderMode: CanvasRenderMode = .wireframe

    /// XY offset for the toolpath preview draws, forwarded straight through
    /// in `updateNSView` — same "plain `let`, flows one-way from
    /// `CanvasSceneModel`" treatment as `renderMode` above. See
    /// `MetalRenderer.xyOffset`.
    var xyOffset: SIMD2<Float> = .zero

    /// M4: the heightmap surface to draw when `renderMode == .heightmap`.
    /// `nil` until `CanvasSceneModel.updateHeightmap` has run at least once
    /// (or if it ran with no assigned tool). Re-uploaded to the GPU only
    /// when it's actually a new mesh — see `Coordinator.lastHeightmapMeshID`.
    var heightmapMesh: HeightmapMesh?

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

        // Plain left-button drag and Shift+drag. handlePan tells these two
        // apart via the Shift modifier and looks up what each one should do
        // in CanvasInputSettings (see CanvasControlsSettingsView).
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        mtkView.addGestureRecognizer(panGesture)

        // Middle-button drag, its own recognizer so handlePan can tell it
        // apart from the two above (see `middleDragGesture` below) and look
        // its own action up in CanvasInputSettings independently.
        let middleDragGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        middleDragGesture.buttonMask = 0x4 // middle mouse button
        mtkView.addGestureRecognizer(middleDragGesture)
        context.coordinator.middleDragGesture = middleDragGesture

        // Trackpad pinch → zoom
        let magnification = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnification(_:)))
        mtkView.addGestureRecognizer(magnification)

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.updateGeometry(objects: objects)
        context.coordinator.renderer?.renderMode = renderMode
        context.coordinator.renderer?.xyOffset = xyOffset

        // `HeightmapMesh.id` is fresh per `init`, so this tells "a new carve
        // landed" apart from "this view's body just re-ran for an unrelated
        // reason" (e.g. a scrub tick touching `objects`) without diffing the
        // mesh's own vertex/index arrays — see `updateHeightmapMesh`'s doc
        // comment on why re-uploading isn't meant to happen every frame.
        if context.coordinator.lastHeightmapMeshID != heightmapMesh?.id {
            context.coordinator.renderer?.updateHeightmapMesh(heightmapMesh)
            context.coordinator.lastHeightmapMeshID = heightmapMesh?.id
        }

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
        /// M4: id of the last `HeightmapMesh` actually uploaded to the GPU
        /// (see `updateNSView`). `nil` alongside `heightmapMesh == nil`
        /// means nothing's been uploaded yet.
        var lastHeightmapMeshID: UUID?
        /// Weak: so the view — which owns the coordinator via AppKit's
        /// retain graph, not the other way around — can be requested to
        /// draw() from the gesture handlers below without creating a cycle.
        weak var metalView: MTKView?
        /// The second drag recognizer, set up in `makeNSView` to fire only
        /// on middle-button drags. `handlePan` checks gesture identity
        /// against this to tell a middle-button drag apart from a
        /// left-button one — both call the same handler.
        weak var middleDragGesture: NSPanGestureRecognizer?
        private var lastMousePosition: CGPoint = .zero

        init(_ parent: MetalCanvasView) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard renderer?.camera != nil else {
                return
            }
            let translation = gesture.translation(in: gesture.view)

            // Which physical input this drag is, so the right entry of
            // CanvasInputSettings applies. Shift+left-drag and a plain
            // left-drag are told apart by the modifier flag; middle-button
            // drag is its own recognizer (see `middleDragGesture`), never
            // this one with the modifier held.
            let trigger: CanvasInputTrigger
            if gesture === middleDragGesture {
                trigger = .middleButton
            } else if NSEvent.modifierFlags.contains(.shift) {
                trigger = .modified
            } else {
                trigger = .primary
            }

            // Reassigning a trigger in CanvasControlsSettingsView takes
            // effect immediately since this looks the mapping up fresh on
            // every drag rather than caching it.
            switch CanvasInputSettings.shared.action(for: trigger) {
            case .orbit:
                performOrbit(translation: translation)
            case .pan:
                performPan(translation: translation)
            case .zoom:
                performDragZoom(translation: translation)
            case .zoomToCursor:
                performDragZoomToCursor(gesture: gesture, translation: translation)
            case .none:
                break
            }

            gesture.setTranslation(.zero, in: gesture.view)
            metalView?.draw()
        }

        /// Rotates the camera around `target`.
        private func performOrbit(translation: CGPoint) {
            guard let camera = renderer?.camera else {
                return
            }
            let sensitivity: Float = 0.005
            camera.rotation.y -= Float(translation.x) * sensitivity
            camera.rotation.x = max(-.pi/2 + 0.0, min(.pi/2 - 0.0, camera.rotation.x + Float(translation.y) * sensitivity))

            // --- PRINT ROTATION VALUES ---
//            let pitchDeg = camera.rotation.x * 180 / .pi
//            let yawDeg = camera.rotation.y * 180 / .pi
//            print(String(format: "🎥 Pitch (X): %.2f rad (%.1f°) | Yaw (Y): %.2f rad (%.1f°)", camera.rotation.x, pitchDeg, camera.rotation.y, yawDeg))
        }

        /// Slides `target` in the view plane, keeping the camera's facing
        /// unchanged. The distance moved per point of pointer travel is
        /// derived from the current zoom (see `Camera.pan`), so the scene
        /// tracks the pointer by the same on-screen amount at any zoom.
        private func performPan(translation: CGPoint) {
            guard let camera = renderer?.camera,
                  let viewportHeight = metalView?.bounds.height,
                  viewportHeight > 0 else {
                return
            }
            camera.pan(by: SIMD2<Float>(Float(translation.x), Float(translation.y)),
                       viewportHeight: Float(viewportHeight))
        }

        /// Zooms by vertical drag distance, for when a trigger is assigned
        /// `.zoom` instead of the usual scroll/pinch. Continuous like a
        /// slider rather than stepped — dragging is a smooth motion, so
        /// there's no "notch" to make grainy the way a wheel click has.
        private func performDragZoom(translation: CGPoint) {
            guard let camera = renderer?.camera else {
                return
            }
            let sensitivity: Float = 0.01
            camera.distance -= Float(translation.y) * (camera.distance * sensitivity)
            clampZoomDistance(camera)
        }

        /// Same idea as `performDragZoom`, but keeps the world point under
        /// the cursor fixed on screen (like pinch) instead of zooming
        /// toward `target`. Finer than `performDragZoom` to match — the
        /// point is more careful, cursor-anchored control.
        private func performDragZoomToCursor(gesture: NSPanGestureRecognizer, translation: CGPoint) {
            guard let camera = renderer?.camera, let view = gesture.view else {
                return
            }
            let sensitivity: Float = 0.006
            let newDistance = camera.distance - Float(translation.y) * (camera.distance * sensitivity)
            applyZoom(to: newDistance, towards: gesture.location(in: view), in: view)
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            // Optional: Handle selection / Raycasting targeting
        }

        @objc func handleMagnification( _ gesture: NSMagnificationGestureRecognizer) {
            guard let camera = renderer?.camera, let view = gesture.view else {
                return
            }
            if gesture.state == .changed {
                // Reads camera.distance itself — the same value every other
                // zoom path reads and writes — rather than a separately
                // tracked "current zoom" float. That old separate variable
                // is what let pinch and scroll drift apart: whichever one
                // you used last silently moved `camera.distance` out from
                // under the other's own private zoom level, so switching
                // between them produced a jump instead of continuing
                // smoothly from wherever the last zoom left off.
                let amount = Float(gesture.magnification)
                let newDistance = camera.distance * (1 - amount)

                applyZoom(to: newDistance, towards: gesture.location(in: view), in: view)
                gesture.magnification = 0
                metalView?.draw()
            }
        }

        func handleScroll(_ event: NSEvent) {
            // Reassigning Scroll / Shift + Scroll in CanvasControlsSettingsView
            // takes effect immediately since this looks the mapping up fresh
            // on every scroll event rather than caching it. Shift is read
            // from the event itself (not `NSEvent.modifierFlags`) so it
            // reflects the state at the moment this scroll was generated.
            let trigger: CanvasInputTrigger = event.modifierFlags.contains(.shift)
                ? .modifiedScroll
                : .scroll
            switch CanvasInputSettings.shared.action(for: trigger) {
            case .zoom:
                if event.hasPreciseScrollingDeltas {
                    // Trackpad two-finger swipe: fine deltas, smooth continuous zoom.
                    performSmoothZoom(deltaY: Float(event.scrollingDeltaY))
                } else {
                    // Standard mouse wheel: one notch at a time, stepped zoom.
                    performSteppedZoom(deltaY: Float(event.scrollingDeltaY))
                }
            case .zoomToCursor:
                performCursorZoom(event: event)
            case .orbit:
                performOrbit(translation: scrollTranslation(event))
            case .pan:
                performPan(translation: scrollTranslation(event))
            case .none:
                break
            }
            metalView?.draw()
        }

        /// Scroll events carry deltas, not a running translation like a
        /// drag gesture does — this adapts one to the other so a scroll
        /// assigned to Orbit or Pan can reuse `performOrbit`/`performPan`
        /// unchanged. The scale factor roughly matches how far a drag would
        /// need to travel to produce the same-feeling amount of rotation/pan.
        private func scrollTranslation(_ event: NSEvent) -> CGPoint {
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 4.0
            return CGPoint(x: -event.scrollingDeltaX * scale, y: event.scrollingDeltaY * scale)
        }

        /// Continuous, exponential-feeling zoom for trackpad/precise scroll.
        private func performSmoothZoom(deltaY: Float) {
            guard let camera = renderer?.camera else {
                return
            }
            let zoomSensitivity: Float = 0.5
            let delta = deltaY * zoomSensitivity
            camera.distance -= delta * (camera.distance * 0.02)
            clampZoomDistance(camera)
        }

        /// Coarser, "grainier" zoom for a standard mouse wheel: each notch
        /// moves by one fixed step rather than blending smoothly, which is
        /// how scroll-to-zoom feels on typical CAD-mouse setups.
        private func performSteppedZoom(deltaY: Float) {
            guard let camera = renderer?.camera else {
                return
            }
            guard deltaY != 0 else {
                return
            }
            let notch: Float = deltaY > 0 ? 1 : -1
            let stepPercent: Float = 0.08
            camera.distance -= notch * max(2.0, camera.distance * stepPercent)
            clampZoomDistance(camera)
        }

        /// Finer, slower zoom that keeps the world point under the cursor
        /// fixed on screen, the same way pinch-to-zoom does (see
        /// `applyZoom`). The scroll default, since a careful, cursor-
        /// anchored zoom is generally what you want from the main zoom
        /// input. The percentages here are well under `performSmoothZoom`'s
        /// 0.02 and `performSteppedZoom`'s 0.08 on purpose — this is meant
        /// to read as noticeably more controlled than either.
        private func performCursorZoom(event: NSEvent) {
            guard let camera = renderer?.camera, let view = metalView else {
                return
            }
            let newDistance: Float
            if event.hasPreciseScrollingDeltas {
                newDistance = camera.distance - Float(event.scrollingDeltaY) * (camera.distance * 0.004)
            } else {
                guard event.scrollingDeltaY != 0 else {
                    return
                }
                let notch: Float = event.scrollingDeltaY > 0 ? 1 : -1
                newDistance = camera.distance - notch * max(1.0, camera.distance * 0.02)
            }
            let location = view.convert(event.locationInWindow, from: nil)
            applyZoom(to: newDistance, towards: location, in: view)
        }

        /// Shared by every cursor-anchored zoom (pinch, `.zoomToCursor` on
        /// scroll or drag): clamps `newDistance`, converts `location` (in
        /// `view`'s own coordinate space) to normalized device coords, and
        /// hands both to `Camera.zoom(to:towards:)`, which keeps whatever
        /// world point sits under that point fixed on screen.
        private func applyZoom(to newDistance: Float, towards location: CGPoint, in view: NSView) {
            guard let camera = renderer?.camera else {
                return
            }
            let clamped = clampedDistance(newDistance)
            let size = view.bounds.size
            guard size.width > 0, size.height > 0 else {
                camera.distance = clamped
                return
            }
            let ndc = SIMD2<Float>(
                Float(location.x / size.width) * 2 - 1,
                Float(location.y / size.height) * 2 - 1
            )
            camera.zoom(to: clamped, towards: ndc)
        }

        /// Clamp distance to prevent clipping into target or zooming out into infinity.
        private func clampedDistance(_ distance: Float) -> Float {
            max(2.0, min(2000.0, distance))
        }

        private func clampZoomDistance(_ camera: Camera) {
            camera.distance = clampedDistance(camera.distance)
        }
    }
}
