//
//  QuickActionTile.swift
//  Stratum CNC
//
//  A small action box for the top group of the projects page: an icon, a
//  title and one line saying what it does.
//

import SwiftUI

struct QuickActionTile: View {

    /// Which tile this is, for the usage tracking that drives the icon tint.
    let usageID: QuickActionID
    let title: String
    let subtitle: String
    let systemImage: String
    var iconRotation: Angle = .zero
    /// A drawing to show instead of the SF Symbol, for icons SF Symbols doesn't have.
    var glyph: AnyView? = nil
    let action: () -> Void

    @ObservedObject private var usage = QuickActionUsage.shared
    @State private var isHovered = false

    var body: some View {
        // 0 = rarely used (plain icon), 1 = most used (fully tinted).
        let intensity = usage.intensity(for: usageID)

        Button(action: {
            usage.recordClick(usageID)
            action()
        }) {
            HStack(spacing: 12) {
                ZStack {
                    icon.foregroundStyle(.secondary)
                    icon.foregroundStyle(.tint).opacity(intensity)
                }
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.10))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.tint.opacity(0.14 * intensity))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .frame(minHeight: 76)
            .background(.quaternary.opacity(isHovered ? 1.0 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isHovered ? Color.primary.opacity(0.5) : Color.secondary.opacity(0.25))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
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
                .font(.system(size: 18, weight: .medium))
                .rotationEffect(iconRotation)
        }
    }
}
