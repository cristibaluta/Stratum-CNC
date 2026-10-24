//
//  PanelStyle.swift
//  Stratum CNC
//
//  Shared low-weight styling for the controller's dense panels and the
//  canvas overlays. The default bordered buttons carry a lot of visual
//  weight when a panel has four or five of them in a row; these keep the
//  controls discoverable while letting the data (positions, the 3D view)
//  stay the loudest thing on screen. `PanelJog` is deliberately untouched.
//

import SwiftUI

/// Small, flat button with a faint fill — for rows of short actions
/// ("X Y Z", "Probe", "Start") where `.bordered` is too heavy.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color = .primary

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(tint.opacity(configuration.isPressed ? 0.22 : 0.10))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 5))
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

/// Fixed-width caption that names a row inside a panel ("ZERO", "PROBE"),
/// so the buttons of consecutive rows line up in a column.
struct PanelRowLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .leading)
    }
}

extension View {
    /// Translucent rounded chrome for controls floating over the 3D canvas.
    /// Replaces the flat `.gray` backgrounds, which read as opaque slabs on
    /// top of the model and clashed with light mode.
    func canvasChrome() -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}
