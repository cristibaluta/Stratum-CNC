//
//  QuickActionTile.swift
//  Stratum CNC
//
//  A small action box for the top group of the projects page: an icon, a
//  title and one line saying what it does.
//

import SwiftUI

struct QuickActionTile: View {

    let title: String
    let subtitle: String
    let systemImage: String
    var iconRotation: Angle = .zero
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .rotationEffect(iconRotation)
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

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
}
