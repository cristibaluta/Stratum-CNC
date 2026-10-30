//
//  QuickActionGroup.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 29.10.2026.
//


//
//  QuickActionRow.swift
//  Stratum CNC
//
//  One row of a grouped list on the projects page (Quick Start, Libraries):
//  an icon chip, a title, one line saying what it does, and a chevron.
//  Replaces QuickActionTile.
//
//  The icon is tinted by how much the user uses the action (see
//  QuickActionUsage): plain when it's rarely used, the full tint when it's the
//  most used one, and in between otherwise.
//

import SwiftUI

/// The rounded container that holds a few `QuickActionRow`s, System Settings style.
struct QuickActionGroup<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }
}

struct QuickActionRow: View {

    /// Which action this is, for the usage tracking that drives the icon tint.
    let usageID: QuickActionID
    let title: String
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
            HStack(spacing: 12) {
                ZStack {
                    icon.foregroundStyle(.secondary)
                    icon.foregroundStyle(.tint).opacity(intensity)
                }
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.secondary.opacity(0.10))
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.tint.opacity(0.16 * intensity))
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(isHovered ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var icon: some View {
        if let glyph {
            glyph
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
        }
    }
}
