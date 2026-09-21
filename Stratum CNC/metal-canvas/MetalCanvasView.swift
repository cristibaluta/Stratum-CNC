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

        // Direct mouse forwarding, used only when the owner installs these
        // (CAM's locked 2D view, which needs press/drag/release rather than
        // a pan gesture). Left `nil` — the controller — the events fall
        // through to `super` and the gesture recognizers, exactly as before.
        var onMouseDown: ((NSEvent) -> Void)?
        var onMouseDragged: ((NSEvent) -> Void)?
        var onMouseUp: ((NSEvent) -> Void)?

        override func mouseDown(with event: NSEvent) {
            if let onMouseDown {
                onMouseDown(event)
            } else {
                super.mouseDown(with: event)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            if let onMouseDragged {
                onMouseDragged(event)
            } else {
                super.mouseDragged(with: event)
            }
        }

        override func mouseUp(with event: NSEvent) {
            if let onMouseUp {
                onMouseUp(event)
            } else {
                super.mouseUp(with: event)
            }
        }
    }

    @Binding var objects: [RenderObject]

    /// Which input scheme drives the camera — see `CanvasInteractionMode`.
    /// A plain `let`, like `renderMode` below: nothing downstream ever
    /// needs to change it back once the view's been created for a given
    /// screen (the controller always passes `.free3D`, CAM's 2D view always
    /// passes `.locked2D`), so it's read once in `makeNSView` rather than
    /// re-applied on every `updateNSView`.
    var interactionMode: CanvasInteractionMode = .free3D

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

    /// Base color for the heightmap surface, forwarded straight through in
    /// `updateNSView` — same one-way flow from `CanvasSceneModel` as
    /// `renderMode`/`xyOffset`. See `MetalRenderer.heightmapBaseColor`.
    var stockColor: SIMD4<Float> = SIMD4<Float>(0.75, 0.72, 0.68, 1.0)

    /// M4: the heightmap surface to draw when `renderMode == .heightmap`.
    /// `nil` until `CanvasSceneModel.updateHeightmap` has run at least once
    /// (or if it ran with no assigned tool). Re-uploaded to the GPU only
    /// when it's actually a new mesh — see `Coordinator.lastHeightmapMeshID`.
    var heightmapMesh: HeightmapMesh?

    /// Overrides the renderer's default dark-gray clear color when non-nil.
    /// The controller leaves this `nil` and looks exactly as before; CAM's
    /// canvas passes the window's own background so its (appearance-aware)
    /// path colors keep their contrast in both light and dark mode.
    /// Applied in `updateNSView`, so changing it just needs a redraw.
    var clearColor: SIMD4<Float>? = nil

    /// Receives press / drag / release in `.locked2D` (CAM's shape
    /// selection). Read once in `makeNSView`, like `interactionMode`. When
    /// set, the plain left-button drag is no longer a pan *gesture* — a
    /// recognizer would swallow the mouse events — so the handler's
    /// `pointerDown` answer decides between panning and doing something
    /// else with the drag. Ignored in `.free3D`.
    var pointerHandler: (any CanvasPointerHandler)? = nil

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

        if interactionMode == .locked2D {
            // `Camera`'s own default orientation already matches
            // `StandardView.top` (see its doc comment), so this is belt-
            // and-suspenders rather than strictly required — but making it
            // explicit means a locked 2D view is never at the mercy of
            // `Camera`'s default happening to still be `.top` later. Never
            // orbited away from afterwards: `handlePan`/`handleScroll`
            // below route every input to pan/zoom in this mode, orbit is
            // simply never called.
            renderer.camera.snap(to: .top)
            // Only one face exists in this mode, so a cube for orienting
            // between faces has nothing useful to show.
            renderer.showOrientationCube = false
            // Frame the drawing (and stock), not the 200 mm ruler.
            renderer.fitExcludedRoles = [.ruler]
        }

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
        if interactionMode == .locked2D, let pointerHandler {
            context.coordinator.pointerHandler = pointerHandler
            mtkView.onMouseDown = { [weak coordinator = context.coordinator] event in
                coordinator?.handleMouseDown(event)
            }
            mtkView.onMouseDragged = { [weak coordinator = context.coordinator] event in
                coordinator?.handleMouseDragged(event)
            }
            mtkView.onMouseUp = { [weak coordinator = context.coordinator] event in
                coordinator?.handleMouseUp(event)
            }
        } else {
            let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            mtkView.addGestureRecognizer(panGesture)
        }

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
        if let clearColor {
            nsView.clearColor = MTLClearColor(red: Double(clearColor.x), green: Double(clearColor.y),
                                              blue: Double(clearColor.z), alpha: Double(clearColor.w))
        }
        context.coordinator.renderer?.updateGeometry(objects: objects)
        context.coordinator.renderer?.renderMode = renderMode
        context.coordinator.renderer?.xyOffset = xyOffset
        context.coordinator.renderer?.heightmapBaseColor = stockColor

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

            // Locked 2D (CAM): every drag pans, full stop — see
            // `CanvasInteractionMode.locked2D`. Free 3D (controller): which
            // physical input this drag is decides the right entry of
            // CanvasInputSettings. Shift+left-drag and a plain left-drag
            // are told apart by the modifier flag; middle-button drag is
            // its own recognizer (see `middleDragGesture`), never this one
            // with the modifier held.
            let action: CanvasControlAction
            if parent.interactionMode == .locked2D {
                action = .pan
            } else {
                let trigger: CanvasInputTrigger
                if gesture === middleDragGesture {
                    trigger = .middleButton
                } else if NSEvent.modifierFlags.contains(.shift) {
                    trigger = .modified
                } else {
                    trigger = .primary
                }
                // Reassigning a trigger in CanvasControlsSettingsView takes
                // effect immediately since this looks the mapping up fresh
                // on every drag rather than caching it.
                action = CanvasInputSettings.shared.action(for: trigger)
            }

            switch action {
            case .orbit:
                performOrbit(translation: translation)
            case .pan:
                performPan(translation: translation)
            case .zoom:
                performDragZoom(translation: translation)
            case .zoomToCursor:
                performDragZoomToCursor(gesture: gesture, translation: translation)
            case .snapToFace, .none:
                // Snap to Face only exists for scroll inputs (see
                // `CanvasControlAction.isAvailable(for:)`).
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
            camera.orbit(yaw: -Float(translation.x) * sensitivity,
                         pitch: Float(translation.y) * sensitivity)
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

        // MARK: - Direct mouse (locked 2D with a pointer handler)

        /// Weak: the owner (CAM's scene model) outlives the view.
        weak var pointerHandler: (any CanvasPointerHandler)?
        private var dragAction: CanvasPointerDragAction = .pan
        private var lastDragViewPoint: CGPoint = .zero

        func handleMouseDown(_ event: NSEvent) {
            guard let pointer = pointerEvent(for: event) else {
                dragAction = .pan
                return
            }
            lastDragViewPoint = pointer.viewPoint
            dragAction = pointerHandler?.pointerDown(pointer) ?? .pan
            metalView?.draw()
        }

        func handleMouseDragged(_ event: NSEvent) {
            guard let pointer = pointerEvent(for: event) else {
                return
            }
            // The event was built from the camera as it is *now*; pan after,
            // so the handler sees the point that was actually under the
            // cursor rather than one shifted by this same drag step.
            pointerHandler?.pointerDragged(pointer)

            if dragAction == .pan {
                performPan(translation: CGPoint(x: pointer.viewPoint.x - lastDragViewPoint.x,
                                                y: pointer.viewPoint.y - lastDragViewPoint.y))
            }
            lastDragViewPoint = pointer.viewPoint
            metalView?.draw()
        }

        func handleMouseUp(_ event: NSEvent) {
            if let pointer = pointerEvent(for: event) {
                pointerHandler?.pointerUp(pointer)
            }
            dragAction = .pan
            metalView?.draw()
        }

        /// View point → world point (z = 0) + the zoom, packaged for the
        /// handler. Same view-point → NDC mapping `applyZoom` uses, since
        /// this view isn't flipped (origin bottom-left, y up).
        private func pointerEvent(for event: NSEvent) -> CanvasPointerEvent? {
            guard let camera = renderer?.camera, let view = metalView else {
                return nil
            }
            let size = view.bounds.size
            guard size.width > 0, size.height > 0 else {
                return nil
            }
            let location = view.convert(event.locationInWindow, from: nil)
            let ndc = SIMD2<Float>(Float(location.x / size.width) * 2 - 1,
                                   Float(location.y / size.height) * 2 - 1)
            guard let world = camera.worldPoint(atScreenNDC: ndc) else {
                return nil
            }
            // Same relation `Camera.pan` uses: the view spans
            // 2 * distance * tan(fov/2) world units vertically.
            let worldPerPoint = 2 * camera.distance * tan(camera.fov * 0.5) / Float(size.height)
            return CanvasPointerEvent(worldPoint: CGPoint(x: CGFloat(world.x), y: CGFloat(world.y)),
                                      viewPoint: location,
                                      modifierFlags: event.modifierFlags,
                                      pointsPerWorldUnit: CGFloat(1 / max(worldPerPoint, 1e-9)))
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
            // Locked 2D (CAM): every scroll pans, regardless of modifiers —
            // same as `handlePan` above, and matching the old CoreAnimation
            // 2D canvas's `scrollWheel`, which never distinguished a
            // modified scroll from a plain one either. Free 3D
            // (controller): reassigning Scroll / Shift + Scroll / Option +
            // Scroll in CanvasControlsSettingsView takes effect immediately
            // since this looks the mapping up fresh on every scroll event
            // rather than caching it. Modifiers are read from the event
            // itself (not `NSEvent.modifierFlags`) so they reflect the
            // state at the moment this scroll was generated.
            let action: CanvasControlAction
            if parent.interactionMode == .locked2D {
                action = .pan
            } else {
                let trigger: CanvasInputTrigger
                if event.modifierFlags.contains(.option) {
                    trigger = .optionScroll
                } else if event.modifierFlags.contains(.shift) {
                    trigger = .modifiedScroll
                } else {
                    trigger = .scroll
                }
                action = CanvasInputSettings.shared.action(for: trigger)
            }
            switch action {
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
            case .snapToFace:
                performViewSnap(event)
            case .none:
                break
            }
            metalView?.draw()
        }

        // MARK: - Snap to standard view

        /// Scroll travel (trackpad points) a swipe has to add up to before
        /// it snaps. High enough that resting fingers or a slight drift
        /// don't trigger it, low enough that a short flick does.
        private let snapSwipeThreshold: CGFloat = 40
        /// Minimum time between two snaps from a mouse wheel, which has no
        /// begin/end to tell one flick from the next.
        private let snapWheelCooldown: TimeInterval = 0.25

        private var snapAccumulated = CGPoint.zero
        /// This swipe has already snapped; ignore the rest of it.
        private var snapSwipeConsumed = false
        private var lastWheelSnapTime: TimeInterval = 0

        /// Snaps to the face the swipe points toward — see
        /// `Camera.snapToFace(forSwipe:_:)`.
        ///
        /// A trackpad swipe arrives as dozens of scroll events, then a
        /// momentum tail after the fingers lift. This adds up the deltas of
        /// one swipe and snaps once when they pass `snapSwipeThreshold`,
        /// ignores the rest of that swipe and its momentum, and re-arms when
        /// the next one begins. A mouse wheel has no phases, so there each
        /// notch snaps, rate-limited by `snapWheelCooldown`.
        private func performViewSnap(_ event: NSEvent) {
            guard let camera = renderer?.camera else {
                return
            }

            // Momentum is the coast after the fingers lift — part of a
            // swipe that's already been dealt with.
            guard event.momentumPhase.isEmpty else {
                return
            }

            let isTrackpadSwipe = !event.phase.isEmpty
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                snapAccumulated = .zero
                snapSwipeConsumed = false
            }
            defer {
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                    snapAccumulated = .zero
                    snapSwipeConsumed = false
                }
            }

            if isTrackpadSwipe {
                guard !snapSwipeConsumed else {
                    return
                }
            } else {
                guard event.timestamp - lastWheelSnapTime >= snapWheelCooldown else {
                    return
                }
            }

            snapAccumulated.x += event.scrollingDeltaX
            snapAccumulated.y += event.scrollingDeltaY

            // A wheel notch is one or two "lines", not trackpad points.
            let threshold = event.hasPreciseScrollingDeltas ? snapSwipeThreshold : 1
            guard hypot(snapAccumulated.x, snapAccumulated.y) >= threshold else {
                return
            }

            camera.snapToFace(forSwipe: Float(snapAccumulated.x), Float(snapAccumulated.y))

            snapAccumulated = .zero
            if isTrackpadSwipe {
                snapSwipeConsumed = true
            } else {
                lastWheelSnapTime = event.timestamp
            }
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
