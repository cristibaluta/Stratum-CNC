//
//  NewProjectCard.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct NewProjectCard: View {

    let action: () -> Void

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
            .background(.quaternary.opacity(0.25))
            .clipShape(
                RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        .quaternary,
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: [6]
                        )
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
