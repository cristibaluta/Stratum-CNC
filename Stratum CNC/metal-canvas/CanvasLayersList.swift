//
//  CanvasLayersList.swift
//  Stratum CNC
//
//  Overlay at the canvas's top-left: every object the canvas draws, each
//  with a checkmark to show or hide it, tinted the color it is drawn in.
//  Stock and Anchor carry a gear that opens their settings. Collapses to
//  just its header so it can get out of the way of the model.
//

import SwiftUI

struct CanvasLayersList<StockSettings: View>: View {

    @ObservedObject var scene: CanvasSceneModel
    /// Content of the popover behind the Stock row's gear.
    private let stockSettings: () -> StockSettings

    @State private var isExpanded = true
    @State private var isShowingStockSettings = false
    @State private var isShowingAnchorSettings = false
    @State private var isShowingJobAreaSettings = false

    init(scene: CanvasSceneModel, @ViewBuilder stockSettings: @escaping () -> StockSettings) {
        self.scene = scene
        self.stockSettings = stockSettings
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
                    if layer == .coordinates {
                        Divider()
                    }
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
        let isOn = scene.isVisible(layer)

        return HStack(spacing: 8) {
            Button {
                scene.setVisible(layer, !isOn)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    Text(layer.label)
                        .font(.caption)
                }
                .foregroundStyle(layer.tint ?? Color.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .help(notDrawnInMode ? "Not drawn in heightmap mode"
                                 : (isAvailable ? "Show or hide \(layer.label.lowercased())" : "Nothing to show yet"))

            Spacer(minLength: 0)

            switch layer {
                case .stock:
                    gear(isPresented: $isShowingStockSettings, help: "Stock settings", tint: layer.tint) {
                        stockSettings()
                    }
                case .boundingBox:
                    gear(isPresented: $isShowingJobAreaSettings, help: "Job area settings", tint: layer.tint) {
                        JobAreaSettingsView(scene: scene)
                    }
                case .anchor:
                    gear(isPresented: $isShowingAnchorSettings, help: "Anchor settings", tint: layer.tint) {
                        AnchorSettingsView(scene: scene)
                    }
                default:
                    EmptyView()
            }
        }
    }

    private func gear<Content: View>(isPresented: Binding<Bool>,
                                     help: String,
                                     tint: Color?,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(tint ?? Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .popover(isPresented: isPresented, arrowEdge: .trailing) {
            content()
        }
    }
}
