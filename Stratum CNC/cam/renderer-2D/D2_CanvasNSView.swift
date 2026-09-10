//
//  D2_CanvasNSView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit

// This NSView draws the renderer result into the layer, and manages mouse interaction.
//
// All geometry edits (drag-to-move, inspector fields, nudge/scale/rotate) go
// through D2_CanvasState's mutation methods now — this view never sets a
// D2_Object's properties directly. D2_CanvasState is responsible for
// notifying observers after every edit, which is what keeps the inspector,
// the objects list and the canvas from drifting out of sync with each other.

final class D2_CanvasNSView: NSView {

    private static let rightViewportPadding: CGFloat = 500
    private static let verticalViewportPadding: CGFloat = 100

    private enum DragMode {
        case pan
        case moveObject(UUID)
    }

    /// Setting this to a *different* D2_CanvasState instance (a new document)
    /// re-fits the viewport to the new content. If you just want to repaint
    /// after an in-place edit to the same canvasState, call `refresh()`
    /// instead — see CAM_2D_View.updateNSView for why this distinction matters.
    var canvasState: D2_CanvasState = D2_CanvasState() {
        didSet {
            needsAutoFitAfterLayout = true
            fitContentInViewportIfPossible()
            render()
        }
    }

    private let renderer = D2_CanvasRenderer()
    private let hitTester = PathHitTester(tolerance: 6)

    private var lastDragLocation: CGPoint?
    private var lastDragWorldLocation: CGPoint?
    private var dragMode: DragMode = .pan
    private var panOffset = CGPoint.zero
    private var zoomScale: CGFloat = 3.0
    private var needsAutoFitAfterLayout = false
    /// Currently unused intentionally. This is rotating the whole world, not sure it's useful
    private var rotationAngle: CGFloat = 0

    var currentPathCount: Int {
        canvasState.objects.reduce(0) { $0 + $1.paths.count }
    }

    /// Called whenever pan or zoom changes so the owner can persist the viewport.
    var onViewportChanged: ((CGPoint, CGFloat) -> Void)?

    /// Restores a previously saved viewport, bypassing the auto-fit that would otherwise run.
    func restoreViewport(panOffset: CGPoint, zoomScale: CGFloat) {
        self.panOffset = panOffset
        self.zoomScale = zoomScale
        needsAutoFitAfterLayout = false
        updateWorldTransform()
        canvasState.zoomScale = zoomScale
        render()
    }

    /// Re-renders using the current canvasState without touching the
    /// viewport. Call this after any in-place edit (selection, object edit,
    /// stock/material change) — anything that should repaint but must not
    /// reset the user's current pan/zoom.
    func refresh() {
        render()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool {
        false
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = STColor.textBackgroundColor.cgColor
        layer?.addSublayer(renderer.workLayer)
    }

    override func layout() {
        super.layout()
        renderer.workLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        updateWorldTransform()
        if needsAutoFitAfterLayout {
            fitContentInViewportIfPossible()
            render()
        }
    }

    private func render() {
        renderer.render(state: canvasState)
    }

    private func updateWorldTransform() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: panOffset.x, y: panOffset.y)
        transform = transform.rotated(by: rotationAngle)
        transform = transform.scaledBy(x: zoomScale, y: zoomScale)
        renderer.workLayer.setAffineTransform(transform)

        CATransaction.commit()
    }

    private func fitContentInViewportIfPossible() {
        fitContentInTrueToLifeSize()
        return
        guard !canvasState.objects.isEmpty else {
            needsAutoFitAfterLayout = false
            return
        }

        var unionRect: CGRect?
        for object in canvasState.objects {
            unionRect = unionRect?.union(object.rotatedBounds) ?? object.rotatedBounds
        }
        guard let contentBounds = unionRect, !bounds.isEmpty else {
            return
        }

        let usableWidth = max(bounds.width - Self.rightViewportPadding, 1)
        let usableHeight = max(bounds.height - (Self.verticalViewportPadding * 2), 1)
        let scaleX = usableWidth / max(contentBounds.width, 1)
        let scaleY = usableHeight / max(contentBounds.height, 1)
        zoomScale = min(max(min(scaleX, scaleY), 0.1), 200)

        // Center content inside the usable viewport (left area not covered by toolpaths panel).
        let targetCenter = CGPoint(x: usableWidth / 2, y: bounds.midY)
        let contentCenter = CGPoint(x: contentBounds.midX, y: contentBounds.midY)
        panOffset = CGPoint(x: targetCenter.x - bounds.midX - contentCenter.x * zoomScale,
                            y: targetCenter.y - bounds.midY - contentCenter.y * zoomScale)
        updateWorldTransform()
        canvasState.zoomScale = zoomScale
        needsAutoFitAfterLayout = false
        onViewportChanged?(panOffset, zoomScale)
    }

    private func fitContentInTrueToLifeSize() {
        guard !canvasState.objects.isEmpty else {
            needsAutoFitAfterLayout = false
            return
        }

        var unionRect: CGRect?
        for object in canvasState.objects {
            unionRect = unionRect?.union(object.rotatedBounds) ?? object.rotatedBounds
        }
        guard let contentBounds = unionRect, !bounds.isEmpty else {
            return
        }

        let usableWidth = max(bounds.width - Self.rightViewportPadding, 1)

        // Set zoom scale to physical 1mm : 1pt ratio
        zoomScale = trueToLifeZoomScale

        // Center content inside usable viewport area
        let targetCenter = CGPoint(x: usableWidth / 2, y: bounds.midY)
        let contentCenter = CGPoint(x: contentBounds.midX, y: contentBounds.midY)

        panOffset = CGPoint(
            x: targetCenter.x - bounds.midX - contentCenter.x * zoomScale,
            y: targetCenter.y - bounds.midY - contentCenter.y * zoomScale
        )

        updateWorldTransform()
        canvasState.zoomScale = zoomScale
        needsAutoFitAfterLayout = false
        onViewportChanged?(panOffset, zoomScale)
    }

    override func scrollWheel(with event: NSEvent) {
        panOffset.x -= event.scrollingDeltaX// Scrolling right should move the canvas left
        panOffset.y += event.scrollingDeltaY// Scrolling up should move the canvas down
        updateWorldTransform()
        onViewportChanged?(panOffset, zoomScale)
    }

    override func magnify(with event: NSEvent) {
        let mouse = convert(event.locationInWindow, from: nil)
        let oldScale = zoomScale
        let newScale = min(max(oldScale * (1 + event.magnification), 0.1), 200)
        guard newScale != oldScale else {
            return
        }
        let mouseFromCenter = CGPoint(x: mouse.x - bounds.midX, y: mouse.y - bounds.midY)
        let ratio = newScale / oldScale
        panOffset.x = mouseFromCenter.x - (mouseFromCenter.x - panOffset.x) * ratio
        panOffset.y = mouseFromCenter.y - (mouseFromCenter.y - panOffset.y) * ratio
        zoomScale = newScale
        updateWorldTransform()
        canvasState.zoomScale = zoomScale
        render()
        onViewportChanged?(panOffset, zoomScale)
    }

    override func rotate(with event: NSEvent) {
        /* Intentionally disabled. */
    }

    override func mouseDown(with event: NSEvent) {

        let viewPoint = convert(event.locationInWindow, from: nil)
        lastDragLocation = viewPoint

        guard let worldPoint = layer?.convert(viewPoint, to: renderer.workLayer) else {
            return
        }
        lastDragWorldLocation = worldPoint
        dragMode = .pan

        if let selectedObjectId = canvasState.selectedObjectIDs.first,
           let object = canvasState.object(withID: selectedObjectId),
           let selectedNode = renderer.nodes[selectedObjectId],
           selectedNode.isRotationCenterHit(worldPoint: worldPoint,
                                            worldLayer: renderer.workLayer,
                                            objectScale: object.scale,
                                            zoomScale: zoomScale) {
            canvasState.selectObject(selectedObjectId)
            dragMode = .moveObject(selectedObjectId)
            render()
            return
        }

        // Shift or Cmd held -> extend/toggle the selection instead of replacing it.
        let isMultiSelectModifierDown = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)

        if let hit = hitTester.hitTest(worldPoint: worldPoint,
                                       objects: canvasState.objects,
                                       nodes: renderer.nodes,
                                       worldLayer: renderer.workLayer,
                                       zoomScale: zoomScale) {
            if isMultiSelectModifierDown {
                canvasState.togglePathSelection(objectID: hit.objectID, pathIndex: hit.pathIndex)
            } else {
                canvasState.selectPath(objectID: hit.objectID, pathIndex: hit.pathIndex)
            }
        } else if !isMultiSelectModifierDown {
            // Only clear on an empty-space click when not multi-selecting,
            // so a stray shift/cmd click on empty canvas doesn't wipe the selection.
            canvasState.clearSelection()
        }
        render()
    }

    override func mouseDragged(with event: NSEvent) {

        let location = convert(event.locationInWindow, from: nil)
        guard let worldPoint = layer?.convert(location, to: renderer.workLayer) else {
            return
        }

        guard let last = lastDragLocation else {
            lastDragLocation = location
            lastDragWorldLocation = worldPoint
            return
        }

        switch dragMode {
        case .pan:
            panOffset.x += location.x - last.x
            panOffset.y += location.y - last.y
            updateWorldTransform()

        case .moveObject(let objectID):
            guard let lastWorld = lastDragWorldLocation,
                  let object = canvasState.object(withID: objectID) else {
                break
            }

            let newPosition = CGPoint(x: object.position.x + (worldPoint.x - lastWorld.x),
                                       y: object.position.y + (worldPoint.y - lastWorld.y))
            canvasState.moveObject(objectID, to: newPosition)
            render()
        }

        lastDragLocation = location
        lastDragWorldLocation = worldPoint
    }

    override func mouseUp(with event: NSEvent) {
        if case .pan = dragMode {
            onViewportChanged?(panOffset, zoomScale)
        }
        lastDragLocation = nil
        lastDragWorldLocation = nil
        dragMode = .pan
    }

    private var trueToLifeZoomScale: CGFloat {
        // 1. Get the screen where the NSView currently resides, or default to main
        guard let screen = window?.screen ?? NSScreen.main else {
            return 72.0 / 25.4 // Fallback (~2.835) assuming standard 72 DPI
        }

        return screen.trueToLifeZoomScale(in: window)
    }
}
