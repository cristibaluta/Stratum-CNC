//
//  NewProjectCard.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct NewProjectCard: View {

    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .medium))

                Text("New Project")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .background(.quaternary.opacity(isHovered ? 1.0 : 0.25))
            .clipShape(
                RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary, style: isHovered
                                  ? StrokeStyle(lineWidth: 2, dash: [6])
                                  : StrokeStyle(lineWidth: 1, dash: [6])
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
