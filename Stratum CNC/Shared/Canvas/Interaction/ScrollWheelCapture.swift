//
//  ScrollWheelCapture.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A transparent overlay that only claims scroll-wheel events — every other
/// event type (clicks, drags) falls straight through to whatever SwiftUI
/// view sits underneath. SwiftUI has no native way to observe scrolling
/// over an arbitrary view, so this drops down to AppKit for just that one
/// purpose.
///
/// Meant to sit as an `.overlay` on top of a control you don't want to
/// replace — e.g. scroll-to-scrub over the g-code slider in
/// `ControllerView`, without breaking the slider's own thumb-drag.

struct ScrollWheelCapture: View {

    let onScroll: (CanvasScrollEvent) -> Void

    var body: some View {
        #if os(macOS)
        AppKitScrollWheelCapture(onScroll: onScroll)
        #else
        // Touch has no scroll wheel; the overlay stays out of the way of the slider beneath.
        Color.clear.allowsHitTesting(false)
        #endif
    }
}

#if os(macOS)

private struct AppKitScrollWheelCapture: NSViewRepresentable {

    let onScroll: (CanvasScrollEvent) -> Void

    private final class CaptureView: NSView {
        var onScroll: ((CanvasScrollEvent) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            onScroll?(CanvasScrollEvent(event, in: self))
        }

        /// The trick that makes "capture scroll, pass through everything
        /// else" possible: AppKit hit-tests by asking the frontmost view
        /// whether it wants a given point, and if this always answered
        /// `self`, it would swallow the clicks meant for the slider
        /// beneath it too. Checking the in-flight event's type here means
        /// it only claims itself while a scroll-wheel event is being
        /// routed; for anything else it returns `nil`, and AppKit moves on
        /// to hit-test the view behind it instead.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .scrollWheel else {
                return nil
            }
            return bounds.contains(point) ? self : nil
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = CaptureView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CaptureView)?.onScroll = onScroll
    }
}
#endif
