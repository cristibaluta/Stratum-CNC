//
//  CanvasLayersList.swift
//  Stratum CNC
//
//  Overlay at the canvas's top-left: every object the canvas draws, each
//  with a checkmark to show or hide it, tinted the color it is drawn in.
//  Some rows carry a gear that opens their settings. Collapses to just its
//  header so it can get out of the way of the model.
//
//  The list knows nothing about the canvas it sits on. The owner says which
//  layers to list (a canvas lists only what it has), how to read and change
//  their visibility, and what the gear opens: the controller passes its
//  `CanvasSceneModel`'s state, the CAM screen its own (`CAMLayersOverlay`).
//  Both read the values in `body`, so the owner's view must observe whatever
//  they come from.
//

import SwiftUI

struct CanvasLayersList: View {

    /// The layers to list, in order.
    private let layers: [CanvasLayer]
    private let isVisible: (CanvasLayer) -> Bool
    private let setVisible: (CanvasLayer, Bool) -> Void
    /// Why a layer can't be switched right now ("Nothing to show yet"), or `nil` when it can.
    /// An unavailable layer stays in the list, disabled.
    private let unavailableReason: (CanvasLayer) -> String?
    /// The color the canvas draws a layer in, for tinting its row. `CanvasLayer.tint` unless the
    /// canvas draws it in another one.
    private let tint: (CanvasLayer) -> Color?
    /// What a layer is called in the list. `CanvasLayer.label` unless the canvas names it differently
    /// (CAM calls the anchor its ruler).
    private let label: (CanvasLayer) -> String
    /// The layers that have a gear, and the content of the popover behind it.
    private let settingsLayers: Set<CanvasLayer>
    private let settings: (CanvasLayer) -> AnyView
    /// Extra rows under the layers, after a divider (a canvas option rather than an object).
    private let footer: AnyView?

    @State private var isExpanded = true
    @State private var settingsLayer: CanvasLayer?

    init(layers: [CanvasLayer],
         isVisible: @escaping (CanvasLayer) -> Bool,
         setVisible: @escaping (CanvasLayer, Bool) -> Void,
         unavailableReason: @escaping (CanvasLayer) -> String? = { _ in nil },
         tint: @escaping (CanvasLayer) -> Color? = { $0.tint },
         label: @escaping (CanvasLayer) -> String = { $0.label },
         settingsLayers: Set<CanvasLayer> = [],
         settings: @escaping (CanvasLayer) -> AnyView = { _ in AnyView(EmptyView()) },
         footer: AnyView? = nil) {
        self.layers = layers
        self.isVisible = isVisible
        self.setVisible = setVisible
        self.unavailableReason = unavailableReason
        self.tint = tint
        self.label = label
        self.settingsLayers = settingsLayers
        self.settings = settings
        self.footer = footer
    }

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

                    Text("LEGEND")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Show legend")

            if isExpanded {
                ForEach(layers) { layer in
                    if layer == .coordinates {
                        Divider()
                    }
                    row(for: layer)
                }
                if let footer {
                    Divider()
                    footer
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fixedSize()
        .canvasChrome()
    }

    private func row(for layer: CanvasLayer) -> some View {
        let reason = unavailableReason(layer)
        let isOn = isVisible(layer)
        let layerTint = tint(layer)

        return HStack(spacing: 8) {
            Button {
                setVisible(layer, !isOn)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    Text(label(layer))
                        .font(.caption)
                }
                .foregroundStyle(layerTint ?? Color.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(reason != nil)
            .help(reason ?? "Show or hide \(label(layer).lowercased())")

            Spacer(minLength: 0)

            if settingsLayers.contains(layer) {
                gear(for: layer, tint: layerTint)
            }
        }
    }

    private func gear(for layer: CanvasLayer, tint: Color?) -> some View {
        Button {
            settingsLayer = (settingsLayer == layer) ? nil : layer
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(tint ?? Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(layer.settingsHelp)
        .popover(isPresented: Binding(get: { settingsLayer == layer },
                                      set: { isShown in
                                          if !isShown, settingsLayer == layer {
                                              settingsLayer = nil
                                          }
                                      }),
                 arrowEdge: .trailing) {
            settings(layer)
        }
    }
}
