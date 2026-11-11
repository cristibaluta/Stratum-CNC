//
//  Colors.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//
//  The one place that knows about AppKit vs UIKit. Everything else in the app
//  uses the `ST…` aliases and helpers below instead of `NS…` / `UI…` types.
//

import Foundation
import SwiftUI
import simd

#if os(macOS)

import AppKit

typealias STColor = NSColor
typealias STImage = NSImage
typealias STFont = NSFont
typealias STPoint = NSPoint
typealias STPointArray = NSPointArray
typealias STView = NSView
typealias STViewRepresentable = NSViewRepresentable

extension NSColor {
    static let rampCardBackground = NSColor.controlBackgroundColor
}

extension STColor {
    /// Primary text color (`NSColor.labelColor` / `UIColor.label`).
    static var stLabel: STColor { .labelColor }
    /// Background of editable content, like the CAM canvas.
    static var stTextBackground: STColor { .textBackgroundColor }

    /// sRGB components, for baking into vertex data. A dynamic color resolves
    /// against the appearance that is current when this runs.
    var stRGBA: SIMD4<Float> {
        guard let c = usingColorSpace(.sRGB) else {
            return SIMD4<Float>(0.2, 0.2, 0.2, 1)
        }
        return SIMD4<Float>(Float(c.redComponent), Float(c.greenComponent),
                            Float(c.blueComponent), Float(c.alphaComponent))
    }
}

extension Image {
    init(stImage: STImage) { self.init(nsImage: stImage) }
}

extension Color {
    static var stWindowBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var stControlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var stSeparator: Color { Color(nsColor: .separatorColor) }
}

/// Dynamic system colors (`labelColor` …) are resolved against an appearance.
/// These let the CAM scene bake them for a given `ColorScheme`.
enum STAppearance {

    @MainActor
    static var systemScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    static func perform(as scheme: ColorScheme, _ body: () -> Void) {
        guard let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) else {
            body()
            return
        }
        appearance.performAsCurrentDrawingAppearance(body)
    }
}

/// The running application, for the one notification both platforms share.
enum STApp {
    static var didResignActiveNotification: Notification.Name { NSApplication.didResignActiveNotification }
    static var willTerminateNotification: Notification.Name { NSApplication.willTerminateNotification }
}

enum STPasteboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

#else

import UIKit

typealias STColor = UIColor
typealias STImage = UIImage
typealias STFont = UIFont
typealias STPoint = CGPoint
typealias STPointArray = UnsafeMutablePointer<CGPoint>
typealias STView = UIView
typealias STViewRepresentable = UIViewRepresentable

extension UIColor {
    static let rampCardBackground = UIColor.secondarySystemBackground
}

extension STColor {
    static var stLabel: STColor { .label }
    static var stTextBackground: STColor { .systemBackground }

    var stRGBA: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return SIMD4<Float>(0.2, 0.2, 0.2, 1)
        }
        return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }
}

extension Image {
    init(stImage: STImage) { self.init(uiImage: stImage) }
}

extension Color {
    static var stWindowBackground: Color { Color(uiColor: .systemBackground) }
    static var stControlBackground: Color { Color(uiColor: .secondarySystemBackground) }
    static var stSeparator: Color { Color(uiColor: .separator) }
}

enum STAppearance {

    @MainActor
    static var systemScheme: ColorScheme {
        UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }

    static func perform(as scheme: ColorScheme, _ body: () -> Void) {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        traits.performAsCurrent(body)
    }
}

enum STApp {
    static var didResignActiveNotification: Notification.Name { UIApplication.willResignActiveNotification }
    static var willTerminateNotification: Notification.Name { UIApplication.willTerminateNotification }
}

enum STPasteboard {
    static func copy(_ string: String) {
        UIPasteboard.general.string = string
    }
}

#endif

// MARK: - Styles that exist on macOS only

extension View {
    /// Borderless menu button on macOS; the default menu on iOS.
    func stBorderlessMenuStyle() -> some View {
        #if os(macOS)
        self.menuStyle(.borderlessButton)
        #else
        self
        #endif
    }

    /// Link-looking button on macOS; the default button on iOS.
    func stLinkButtonStyle() -> some View {
        #if os(macOS)
        self.buttonStyle(.link)
        #else
        self.buttonStyle(.borderless)
        #endif
    }

    /// Radio buttons on macOS; the default picker on iOS.
    func stRadioGroupPickerStyle() -> some View {
        #if os(macOS)
        self.pickerStyle(.radioGroup)
        #else
        self.pickerStyle(.menu)
        #endif
    }

    /// Checkbox on macOS (there is none on iOS); a switch on iOS.
    func stCheckboxToggleStyle() -> some View {
        #if os(macOS)
        self.toggleStyle(.checkbox)
        #else
        self.toggleStyle(.switch)
        #endif
    }
}
