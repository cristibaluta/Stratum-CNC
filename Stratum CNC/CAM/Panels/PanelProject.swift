//
//  PanelProject.swift
//  Stratum CNC
//
//  One card for the left side: the Objects and Setups sections as a single project tree, and the
//  send-to-controller footer under them. Replaces two separate cards, so the relationship between
//  objects, setups and toolpaths reads at a glance and less vertical space is spent on chrome.
//

import SwiftUI

/// The card the sections share: padding, clip and the canvas chrome.
struct PanelCardChrome: ViewModifier {

    /// False when the view is a section inside `PanelProject`, which draws the card.
    let isCard: Bool

    func body(content: Content) -> some View {
        if isCard {
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .canvasChrome()
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A single card with the sections (`PanelObjectsInspector`, `PanelSetups`, both `embedded`) and a
/// footer. Put a `Divider().padding(.vertical, 8)` between sections.
struct PanelProject<Content: View, Footer: View>: View {

    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            footer()
        }
        .modifier(PanelCardChrome(isCard: true))
    }
}
