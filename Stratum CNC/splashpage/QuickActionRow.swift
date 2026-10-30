//
//  QuickActionGroup.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 29.10.2026.
//
//  One row of a list on the projects page (Quick Start, Libraries), in the style of
//  Xcode's welcome window and Finder's sidebar rather than an iOS grouped list: no
//  container card, no disclosure chevrons, no icon chips. An icon and a title (what the
//  action does is its tooltip); a rounded highlight under the pointer.
//  Replaces QuickActionTile.
//
//  The icon is tinted by how much the user uses the action (see
//  QuickActionUsage): plain when it's rarely used, the full tint when it's the
//  most used one, and in between otherwise.
//

import SwiftUI

/// The rows of one section, stacked with a little air between them. No card around them:
/// they sit straight on the window, like a sidebar's items.
struct QuickActionGroup<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
    }
}

struct QuickActionRow: View {

    /// Which action this is, for the usage tracking that drives the icon tint.
    let usageID: QuickActionID
    let title: String
    /// What the action does, shown as the help tooltip instead of a second line.
    let subtitle: String
    let systemImage: String
    /// A drawing to show instead of the SF Symbol, for icons SF Symbols doesn't have.
    var glyph: AnyView? = nil
    let action: () -> Void

    @ObservedObject private var usage = QuickActionUsage.shared
    @State private var isHovered = false

    var body: some View {
        // 0 = rarely used (plain icon), 1 = most used (fully tinted).
        let intensity = usage.intensity(for: usageID)

        Button {
            usage.recordClick(usageID)
            action()
        } label: {
            HStack(spacing: 10) {
                // A plain glyph, gray until the action is used a lot, then in the accent color
                ZStack {
                    icon.foregroundStyle(.secondary)
                    icon.foregroundStyle(.tint).opacity(intensity)
                }
                .frame(width: 24, height: 24)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(subtitle)
        .onHover {
            isHovered = $0
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let glyph {
            glyph
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .regular))
        }
    }
}
