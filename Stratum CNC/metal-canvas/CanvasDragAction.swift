//
//  CanvasInputSettings.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//

import Foundation

/// What a mouse input does to the 3D canvas.
enum CanvasControlAction: String, CaseIterable, Identifiable {
    case orbit
    case pan
    /// Fast, coarse zoom centered on the current orbit target — the
    /// original scroll/drag zoom.
    case zoom
    /// Finer, slower zoom that keeps the world point under the cursor
    /// fixed on screen, the same way pinch-to-zoom does. The default for
    /// `.scroll` since scroll is usually the primary zoom input and this
    /// reads as more controlled than `.zoom`.
    case zoomToCursor
    /// Jumps between the six standard views (top, bottom, front, back, left,
    /// right) — one jump per swipe, toward the side the swipe points to. Only
    /// meaningful for scroll inputs; see `isAvailable(for:)`.
    case snapToView
    case none

    var id: String { rawValue }

    /// Snapping to a view needs a discrete swipe, which a drag or a mouse
    /// button doesn't provide, so it's only offered for the scroll triggers.
    func isAvailable(for trigger: CanvasInputTrigger) -> Bool {
        self != .snapToView || trigger.isScroll
    }

    var label: String {
        switch self {
        case .orbit: return "Orbit"
        case .pan: return "Pan"
        case .zoom: return "Zoom"
        case .zoomToCursor: return "Zoom to Cursor"
        case .snapToView: return "Snap to View"
        case .none: return "Do Nothing"
        }
    }
}

/// One mouse input the user can control the canvas with. Each is
/// independently assignable to a `CanvasControlAction` in
/// `CanvasControlsSettingsView`.
///
/// Trackpad pinch isn't included here — it's a distinct gesture
/// (`NSMagnificationGestureRecognizer`) that only ever means zoom, so
/// there's nothing to reassign it to. `.scroll` covers the mouse wheel and
/// a two-finger trackpad swipe instead, both of which arrive as
/// `scrollWheel(with:)` and — unlike pinch — are just as usable for
/// orbit/pan as for zoom.
enum CanvasInputTrigger: String, CaseIterable, Identifiable {
    case primary       // Plain left-button drag
    case modified      // Shift + left-button drag
    case middleButton  // Middle-button drag
    case scroll        // Scroll wheel / two-finger trackpad swipe
    case modifiedScroll // Shift + scroll wheel / two-finger trackpad swipe
    case optionScroll   // Option + scroll wheel / two-finger trackpad swipe

    var id: String { rawValue }

    var isScroll: Bool {
        switch self {
        case .scroll, .modifiedScroll, .optionScroll: return true
        case .primary, .modified, .middleButton: return false
        }
    }

    var label: String {
        switch self {
        case .primary: return "Drag"
        case .modified: return "Shift + Drag"
        case .middleButton: return "Middle-Click Drag"
        case .scroll: return "Scroll"
        case .modifiedScroll: return "Shift + Scroll"
        case .optionScroll: return "Option + Scroll"
        }
    }
}

/// Persisted mapping from mouse input → canvas action. `MetalCanvasView`'s
/// coordinator reads `.shared` live on every drag/scroll event rather than
/// caching the mapping, so a change made in `CanvasControlsSettingsView`
/// takes effect on the very next input — no restart, no "Apply" button
/// needed.
@MainActor
final class CanvasInputSettings: ObservableObject {
    static let shared = CanvasInputSettings()

    static let defaultPrimary: CanvasControlAction = .orbit
    static let defaultModified: CanvasControlAction = .pan
    static let defaultMiddleButton: CanvasControlAction = .pan
    static let defaultScroll: CanvasControlAction = .zoomToCursor
    static let defaultModifiedScroll: CanvasControlAction = .orbit
    static let defaultOptionScroll: CanvasControlAction = .snapToView

    @Published var primaryAction: CanvasControlAction {
        didSet { defaults.set(primaryAction.rawValue, forKey: Keys.primary) }
    }
    @Published var modifiedAction: CanvasControlAction {
        didSet { defaults.set(modifiedAction.rawValue, forKey: Keys.modified) }
    }
    @Published var middleButtonAction: CanvasControlAction {
        didSet { defaults.set(middleButtonAction.rawValue, forKey: Keys.middleButton) }
    }
    @Published var scrollAction: CanvasControlAction {
        didSet { defaults.set(scrollAction.rawValue, forKey: Keys.scroll) }
    }

    @Published var modifiedScrollAction: CanvasControlAction {
        didSet { defaults.set(modifiedScrollAction.rawValue, forKey: Keys.modifiedScroll) }
    }

    @Published var optionScrollAction: CanvasControlAction {
        didSet { defaults.set(optionScrollAction.rawValue, forKey: Keys.optionScroll) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let primary = "canvas.input.primary"
        static let modified = "canvas.input.modified"
        static let middleButton = "canvas.input.middleButton"
        static let scroll = "canvas.input.scroll"
        static let modifiedScroll = "canvas.input.modifiedScroll"
        static let optionScroll = "canvas.input.optionScroll"
    }

    /// `defaults` is injectable (rather than always `.standard`) so a test
    /// or a future "reset everything" flow can point this at a throwaway
    /// suite instead of touching the user's real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        primaryAction = CanvasControlAction(rawValue: defaults.string(forKey: Keys.primary) ?? "")
            ?? Self.defaultPrimary
        modifiedAction = CanvasControlAction(rawValue: defaults.string(forKey: Keys.modified) ?? "")
            ?? Self.defaultModified
        middleButtonAction = CanvasControlAction(rawValue: defaults.string(forKey: Keys.middleButton) ?? "")
            ?? Self.defaultMiddleButton
        scrollAction = CanvasControlAction(rawValue: defaults.string(forKey: Keys.scroll) ?? "")
            ?? Self.defaultScroll
        modifiedScrollAction = CanvasControlAction(rawValue: defaults.string(forKey: Keys.modifiedScroll) ?? "")
            ?? Self.defaultModifiedScroll
        optionScrollAction = CanvasControlAction(rawValue: defaults.string(forKey: Keys.optionScroll) ?? "")
            ?? Self.defaultOptionScroll
    }

    func action(for trigger: CanvasInputTrigger) -> CanvasControlAction {
        switch trigger {
        case .primary: return primaryAction
        case .modified: return modifiedAction
        case .middleButton: return middleButtonAction
        case .scroll: return scrollAction
        case .modifiedScroll: return modifiedScrollAction
        case .optionScroll: return optionScrollAction
        }
    }

    func setAction(_ action: CanvasControlAction, for trigger: CanvasInputTrigger) {
        switch trigger {
        case .primary: primaryAction = action
        case .modified: modifiedAction = action
        case .middleButton: middleButtonAction = action
        case .scroll: scrollAction = action
        case .modifiedScroll: modifiedScrollAction = action
        case .optionScroll: optionScrollAction = action
        }
    }

    func restoreDefaults() {
        primaryAction = Self.defaultPrimary
        modifiedAction = Self.defaultModified
        middleButtonAction = Self.defaultMiddleButton
        scrollAction = Self.defaultScroll
        modifiedScrollAction = Self.defaultModifiedScroll
        optionScrollAction = Self.defaultOptionScroll
    }
}
