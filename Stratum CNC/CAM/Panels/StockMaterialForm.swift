//
//  StockMaterialForm.swift
//  Stratum CNC
//
//  The stock's editable fields: material, shape and the dimensions that shape needs.
//  Just the form, with no title, summary line or visibility button around it, so it can sit
//  inside another container: CAM's `PanelStockMaterial` shows it under its summary line, and
//  the Controller's legend opens it as is from the stock's gear.
//

import SwiftUI

struct StockMaterialForm: View {

    @Binding var stock: StockMaterial

    var body: some View {
        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            InspectorRow(label: "Material") {
                Menu {
                    ForEach(StockMaterialType.allCases, id: \.self) { material in
                        Button {
                            // A name that is just the old material's (a new project starts as
                            // "Aluminum") follows the change. A name picked from the library stays.
                            if stock.name.caseInsensitiveCompare(stock.material.displayName) == .orderedSame {
                                stock.name = material.displayName
                            }
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
