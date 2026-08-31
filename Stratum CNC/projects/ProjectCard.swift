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
        .clipShape(
            RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
