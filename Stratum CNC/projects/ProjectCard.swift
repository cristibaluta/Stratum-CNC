//
//  ProjectCard.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct ProjectCard: View {

    let project: Project
    let previewURL: URL
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            ProjectPreview(url: previewURL)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.5))
                .clipShape(
                    RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(project.modifiedAt, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .background(.background)
        .contentShape(
            RoundedRectangle(cornerRadius: 12)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? .primary : .quaternary)
        }
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0), radius: isHovered ? 10 : 0, x: 0, y: 4)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
