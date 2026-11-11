//
//  CanvasInputEvents.swift
//  Stratum CNC
//
//  Platform-neutral input for `MetalCanvasView`. AppKit hands it `NSEvent`s and
//  UIKit hands it touches and gesture recognizers; both are converted to these
//  at the edge of the view so the camera and click logic are written once.
//
//  Every location here is in the view's own coordinates in points with the
//  origin at the BOTTOM-left (AppKit's un-flipped convention, which the camera
//  math expects). UIKit's top-left locations are flipped on the way in.
//

import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CanvasModifiers: OptionSet {
    let rawValue: Int

    static let shift = CanvasModifiers(rawValue: 1 << 0)
    static let option = CanvasModifiers(rawValue: 1 << 1)
    static let command = CanvasModifiers(rawValue: 1 << 2)
}

struct CanvasScrollPhase: OptionSet {
    let rawValue: Int

    static let began = CanvasScrollPhase(rawValue: 1 << 0)
    static let mayBegin = CanvasScrollPhase(rawValue: 1 << 1)
    static let changed = CanvasScrollPhase(rawValue: 1 << 2)
    static let ended = CanvasScrollPhase(rawValue: 1 << 3)
    static let cancelled = CanvasScrollPhase(rawValue: 1 << 4)
}

/// A press, drag or release of the primary pointer (mouse button or finger).
struct CanvasMouseEvent {
    /// In the view, origin bottom-left.
    var location: CGPoint
    var modifiers: CanvasModifiers = []
    /// 1 for a single click, 2 for the second click of a double click.
    var clickCount: Int = 1
}

/// One scroll-wheel / trackpad-swipe event. Only AppKit produces these.
struct CanvasScrollEvent {
    var scrollingDeltaX: CGFloat
    var scrollingDeltaY: CGFloat
    var hasPreciseScrollingDeltas: Bool
    var modifiers: CanvasModifiers
    /// In the view, origin bottom-left.
    var location: CGPoint
    var phase: CanvasScrollPhase
    var momentumPhase: CanvasScrollPhase
    var timestamp: TimeInterval
}

#if os(macOS)

extension CanvasModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: CanvasModifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }

    /// The modifier keys held right now.
    static var current: CanvasModifiers {
        CanvasModifiers(NSEvent.modifierFlags)
    }
}

extension CanvasScrollPhase {
    init(_ phase: NSEvent.Phase) {
        var result: CanvasScrollPhase = []
        if phase.contains(.began) { result.insert(.began) }
        if phase.contains(.mayBegin) { result.insert(.mayBegin) }
        if phase.contains(.changed) { result.insert(.changed) }
        if phase.contains(.ended) { result.insert(.ended) }
        if phase.contains(.cancelled) { result.insert(.cancelled) }
        self = result
    }
}

extension CanvasMouseEvent {
    @MainActor
    init(_ event: NSEvent, in view: NSView) {
        self.init(location: view.convert(event.locationInWindow, from: nil),
                  modifiers: CanvasModifiers(event.modifierFlags),
                  clickCount: event.clickCount)
    }
}

extension CanvasScrollEvent {
    @MainActor
    init(_ event: NSEvent, in view: NSView) {
        self.init(scrollingDeltaX: event.scrollingDeltaX,
                  scrollingDeltaY: event.scrollingDeltaY,
                  hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
                  modifiers: CanvasModifiers(event.modifierFlags),
                  location: view.convert(event.locationInWindow, from: nil),
                  phase: CanvasScrollPhase(event.phase),
                  momentumPhase: CanvasScrollPhase(event.momentumPhase),
                  timestamp: event.timestamp)
    }
}

#else

extension CanvasModifiers {
    init(_ flags: UIKeyModifierFlags) {
        var result: CanvasModifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.alternate) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }

    /// UIKit has no global "keys held right now"; a touch has no modifiers.
    static var current: CanvasModifiers { [] }
}

extension UIView {
    /// A UIKit point (origin top-left) in the canvas convention (origin bottom-left).
    func canvasPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: bounds.height - point.y)
    }
}

#endif
