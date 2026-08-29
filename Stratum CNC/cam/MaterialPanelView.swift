//
//  MaterialPanelView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 29.08.2026.
//

import SwiftUI

struct MaterialPanelView: View {

    @Binding var stock: StockMaterial

    var body: some View {
        GroupBox("MATERIAL") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Picker("Material", selection: $stock.material) {
                        ForEach(StockMaterialType.allCases, id: \.self) { material in
                            Text(material.displayName)
                                .tag(material)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Picker("Shape", selection: shapeBinding) {
                        ForEach(StockShape.allCases, id: \.self) { shape in
                            Text(shape.displayName)
                                .tag(shape)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                dimensionsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private var shapeBinding: Binding<StockShape> {
        Binding(
            get: { stock.geometry.shape },
            set: { stock.geometry = defaultGeometry(for: $0) }
        )
    }

    @ViewBuilder
    private var dimensionsRow: some View {
        switch stock.geometry {
        case .rectangular(let length, let width, let height):
            HStack(spacing: 8) {
                dimensionField(label: "L", value: Binding(
                    get: { length },
                    set: { stock.geometry = .rectangular(width: $0, height: width, depth: height) }
                ))
                dimensionField(label: "l", value: Binding(
                    get: { width },
                    set: { stock.geometry = .rectangular(width: length, height: $0, depth: height) }
                ))
                dimensionField(label: "h", value: Binding(
                    get: { height },
                    set: { stock.geometry = .rectangular(width: length, height: width, depth: $0) }
                ))
            }

        case .round(let diameter, let height):
            HStack(spacing: 8) {
                dimensionField(label: "D", value: Binding(
                    get: { diameter },
                    set: { stock.geometry = .round(diameter: $0, depth: height) }
                ))
                dimensionField(label: "h", value: Binding(
                    get: { height },
                    set: { stock.geometry = .round(diameter: diameter, depth: $0) }
                ))
                Spacer(minLength: 0)
            }

        case .disk(let outerDiameter, let innerDiameter, let height):
            HStack(spacing: 8) {
                dimensionField(label: "D ext", value: Binding(
                    get: { outerDiameter },
                    set: { stock.geometry = .disk(outerDiameter: $0, innerDiameter: innerDiameter, depth: height) }
                ))
                dimensionField(label: "D int", value: Binding(
                    get: { innerDiameter },
                    set: { stock.geometry = .disk(outerDiameter: outerDiameter, innerDiameter: $0, depth: height) }
                ))
                dimensionField(label: "h", value: Binding(
                    get: { height },
                    set: { stock.geometry = .disk(outerDiameter: outerDiameter, innerDiameter: innerDiameter, depth: $0) }
                ))
            }
        }
    }

    private func defaultGeometry(for shape: StockShape) -> StockGeometry {
        switch shape {
        case .rectangular:
            return .rectangular(width: 100, height: 50, depth: 10)
        case .round:
            return .round(diameter: 20, depth: 100)
        case .disk:
            return .disk(outerDiameter: 30, innerDiameter: 20, depth: 100)
        }
    }

    private func dimensionField(label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder)

            Text("mm")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
