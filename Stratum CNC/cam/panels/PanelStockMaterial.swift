//
//  MaterialPanelView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 29.08.2026.
//

import SwiftUI

struct PanelStockMaterial: View {

    @Binding var stock: StockMaterial
    @Binding var isStockVisible: Bool
    let isCompact: Bool
    var onOpenStocksLib: (() async -> StockMaterial?)?
    /// When set, the library button opens the stocks library in a popover instead of calling `onOpenStocksLib`.
    var stocksStore: StocksStore? = nil

    @State private var showingLibrary = false

    /// Collapsed, the panel is one line. Clicking it opens the editable details.
    @State private var isExpanded = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                summaryLine
                if isExpanded {
                    details
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    // MARK: Summary

    /// Visibility, library, then "Material · Shape · size" -- all on one line.
    private var summaryLine: some View {
        HStack(spacing: 8) {
            if !isCompact {
                visibilityButton
            }

            Button {
                if stocksStore != nil {
                    showingLibrary = true
                    return
                }
                Task {
                    if let returnedItem = await onOpenStocksLib?() {
                        self.stock = returnedItem
                    } else {
                        print("No object selected")
                    }
                }
            } label: {
                Image(systemName: "cube")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Pick from the material library")
            .popover(isPresented: $showingLibrary, arrowEdge: .leading) {
                if let stocksStore {
                    StockSheet(store: stocksStore, onPick: { stock = $0 })
                        .frame(width: 800, height: 600)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(summary)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    InspectorChevron(isExpanded: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide material details" : "Edit material")
        }
    }

    private var summary: String {
        "\(stock.material.displayName) · \(stock.geometry.displayName) · \(sizeText)"
    }

    private var sizeText: String {
        switch stock.geometry {
            case .rectangular(let length, let width, let height):
                return "\(format(length))×\(format(width))×\(format(height)) mm"
            case .cylindrical(let diameter, let length):
                return "Ø\(format(diameter))×\(format(length)) mm"
            case .disk(let outerDiameter, let innerDiameter, let height):
                return "Ø\(format(outerDiameter))/\(format(innerDiameter))×\(format(height)) mm"
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            Divider()
                .padding(.bottom, 2)

            InspectorRow(label: "Material") {
                Menu {
                    ForEach(StockMaterialType.allCases, id: \.self) { material in
                        Button {
                            stock.material = material
                        } label: {
                            if material == stock.material {
                                Label(material.displayName, systemImage: "checkmark")
                            } else {
                                Text(material.displayName)
                            }
                        }
                    }
                } label: {
                    InspectorMenuLabel {
                        Text(stock.material.displayName)
                    }
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
            }

            InspectorRow(label: "Shape") {
                Menu {
                    ForEach(StockGeometry.allCases, id: \.id) { shape in
                        Button {
                            if shape.id != stock.geometry.id {
                                shapeBinding.wrappedValue = shape
                            }
                        } label: {
                            if shape.id == stock.geometry.id {
                                Label(shape.displayName, systemImage: "checkmark")
                            } else {
                                Text(shape.displayName)
                            }
                        }
                    }
                } label: {
                    InspectorMenuLabel {
                        Text(stock.geometry.displayName)
                    }
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
            }

            dimensionsRow
        }
    }

    private var visibilityButton: some View {
        Button {
            isStockVisible.toggle()
        } label: {
            Image(systemName: isStockVisible ? "eye" : "eye.slash")
                .font(.system(size: 12))
                .foregroundStyle(isStockVisible ? .primary : .secondary)
                .frame(width: 18)
        }
        .buttonStyle(.borderless)
        .help(isStockVisible ? "Hide material in 2D" : "Show material in 2D")
    }

    private var shapeBinding: Binding<StockGeometry> {
        Binding(
            get: { stock.geometry },
            set: { stock.geometry = defaultGeometry(for: $0) }
        )
    }

    @ViewBuilder
    private var dimensionsRow: some View {
        switch stock.geometry {
            case .rectangular(let length, let width, let height):
                dimensionField(label: "Length (x)", value: Binding(
                    get: { length },
                    set: { stock.geometry = .rectangular(width: $0, height: width, depth: height) }
                ))
                dimensionField(label: "Width (y)", value: Binding(
                    get: { width },
                    set: { stock.geometry = .rectangular(width: length, height: $0, depth: height) }
                ))
                dimensionField(label: "Height (z)", value: Binding(
                    get: { height },
                    set: { stock.geometry = .rectangular(width: length, height: width, depth: $0) }
                ))

            case .cylindrical(let diameter, let length):
                dimensionField(label: "Diameter", value: Binding(
                    get: { diameter },
                    set: { stock.geometry = .cylindrical(diameter: $0, length: length) }
                ))
                dimensionField(label: "Height (z)", value: Binding(
                    get: { length },
                    set: { stock.geometry = .cylindrical(diameter: diameter, length: $0) }
                ))

            case .disk(let outerDiameter, let innerDiameter, let height):
                dimensionField(label: "Outer Ø", value: Binding(
                    get: { outerDiameter },
                    set: { stock.geometry = .disk(outerDiameter: $0, innerDiameter: innerDiameter, depth: height) }
                ))
                dimensionField(label: "Inner Ø", value: Binding(
                    get: { innerDiameter },
                    set: { stock.geometry = .disk(outerDiameter: outerDiameter, innerDiameter: $0, depth: height) }
                ))
                dimensionField(label: "Height (z)", value: Binding(
                    get: { height },
                    set: { stock.geometry = .disk(outerDiameter: outerDiameter, innerDiameter: innerDiameter, depth: $0) }
                ))
        }
    }

    private func defaultGeometry(for shape: StockGeometry) -> StockGeometry {
        switch shape {
            case .rectangular:
                return .rectangular(width: 100, height: 100, depth: 10)
            case .cylindrical:
                return .cylindrical(diameter: 100, length: 10)
            case .disk:
                return .disk(outerDiameter: 80, innerDiameter: 20, depth: 1.3)
        }
    }

    private func dimensionField(label: String, value: Binding<Double>) -> some View {
        InspectorNumberField(title: label, value: value, suffix: "mm")
    }
}
