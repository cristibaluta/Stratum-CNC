//
//  AddToolpathTooltip.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 11.11.2026.
//

import SwiftUI

struct AddToolpathTooltip: View {

    let shapeCount: Int
    var noun = "shape"
    let onAdd: () -> Void

    private static let arrowSize = CGSize(width: 16, height: 8)

    var body: some View {
        HStack(spacing: 12) {
            Text(shapeCount == 1 ? "1 \(noun) selected" : "\(shapeCount) \(noun)s selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(action: onAdd) {
                Label("Add toolpath", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8 + Self.arrowSize.height)
        .background {
            CalloutShape(arrowSize: Self.arrowSize)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .overlay {
            CalloutShape(arrowSize: Self.arrowSize)
                .stroke(.separator)
        }
    }
}
