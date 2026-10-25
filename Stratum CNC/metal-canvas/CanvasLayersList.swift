//
//  CanvasLayersList.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.10.2026.
//

import SwiftUI

struct CanvasLayersList: View {

    @ObservedObject var scene: CanvasSceneModel

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text("OBJECTS")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Show objects list")

            if isExpanded {
                ForEach(CanvasLayer.allCases) { layer in
                    row(for: layer)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fixedSize()
        .canvasChrome()
    }

    private func row(for layer: CanvasLayer) -> some View {
        let notDrawnInMode = layer.isWireframeOnly && scene.renderMode == .heightmap
        let isAvailable = scene.hasContent(layer) && !notDrawnInMode

        return Toggle(isOn: Binding(get: { scene.isVisible(layer) },
                                    set: { scene.setVisible(layer, $0) })) {
            Text(layer.label)
                .font(.caption)
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .disabled(!isAvailable)
        .help(notDrawnInMode ? "Not drawn in heightmap mode"
                             : (isAvailable ? "Show or hide \(layer.label.lowercased())" : "Nothing to show yet"))
    }
}
