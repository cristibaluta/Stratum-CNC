//
//  CAM_2D_View.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit
import SwiftUI

struct CAM_2D_View: NSViewRepresentable {

    @ObservedObject var canvasState: D2_CanvasState

    /// Viewport to restore on first appearance (e.g. from a previous session), if any.
    var initialViewport: (panOffset: CGPoint, zoomScale: CGFloat)?

    /// Called whenever the user pans or zooms, so the owner can persist the viewport.
    var onViewportChanged: ((CGPoint, CGFloat) -> Void)?

    func makeNSView(context: Context) -> D2_CanvasNSView {

        let view = D2_CanvasNSView()
        view.clipsToBounds = true
        view.canvasState = canvasState
        view.onViewportChanged = onViewportChanged

        if let initialViewport {
            view.restoreViewport(panOffset: initialViewport.panOffset, zoomScale: initialViewport.zoomScale)
        }

        return view
    }

    func updateNSView(_ nsView: D2_CanvasNSView, context: Context) {

        // Only assign canvasState when it's genuinely a *different* instance
        // (e.g. a new document was opened). D2_CanvasNSView re-fits the
        // viewport whenever canvasState is set — reassigning the *same*
        // instance on every unrelated SwiftUI body re-evaluation used to
        // trigger that same re-fit, which is why panning/zooming used to
        // silently reset while just typing in the material panel or inspector.
        if nsView.canvasState !== canvasState {
            nsView.canvasState = canvasState
        } else {
            nsView.refresh()
        }
        nsView.onViewportChanged = onViewportChanged
    }
}
