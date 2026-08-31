//
//  MaterialPanelView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 29.08.2026.
//

import SwiftUI

struct MaterialPanelView: View {

    @Binding var project: ProjectData?
    @Binding var stock: StockMaterial

    var body: some View {
        GroupBox("MATERIAL") {
            HStack(spacing: 8) {
                visibilityButton

                Picker("Material", selection: $stock.material) {
                    ForEach(StockMaterialType.allCases, id: \.self) { material in
                        Text(material.displayName)
                            .tag(material)
                    }
                }
                .labelsHidden()

                Picker("Geometry", selection: shapeBinding) {
                    ForEach(StockGeometry.allCases, id: \.self) { shape in
                        Text(shape.displayName)
                            .tag(shape)
                    }
                }
                .labelsHidden()

                Divider().frame(height: 20)

                dimensionsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var visibilityButton: some View {
        Button {
            project?.isStockVisible?.toggle()
        } label: {
            Image(systemName: project?.isStockVisible ?? false ? "eye" : "eye.slash")
                .foregroundStyle(project?.isStockVisible ?? false ? .primary : .secondary)
                .frame(width: 18)
        }
        .buttonStyle(.borderless)
        .help(project?.isStockVisible ?? false ? "Hide material in 2D" : "Show material in 2D")
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
            dimensionField(label: "L", value: Binding(
                get: { length },
                set: { stock.geometry = .rectangular(width: $0, height: width, depth: height) }
            ))
            dimensionField(label: "l", value: Binding(
                get: { width },
                set: { stock.geometry = .rectangular(width: length, height: $0, depth: height) }
            ))
            dimensionField(label: "h", showUnits: true, value: Binding(
                get: { height },
                set: { stock.geometry = .rectangular(width: length, height: width, depth: $0) }
            ))

        case .cylindrical(let diameter, let length):
            dimensionField(label: "D", value: Binding(
                get: { diameter },
                set: { stock.geometry = .cylindrical(diameter: $0, length: length) }
            ))
            dimensionField(label: "h", showUnits: true, value: Binding(
                get: { length },
                set: { stock.geometry = .cylindrical(diameter: diameter, length: $0) }
            ))

        case .disk(let outerDiameter, let innerDiameter, let height):
            dimensionField(label: "D ext", value: Binding(
                get: { outerDiameter },
                set: { stock.geometry = .disk(outerDiameter: $0, innerDiameter: innerDiameter, depth: height) }
            ))
            dimensionField(label: "D int", value: Binding(
                get: { innerDiameter },
                set: { stock.geometry = .disk(outerDiameter: outerDiameter, innerDiameter: $0, depth: height) }
            ))
            dimensionField(label: "h", showUnits: true, value: Binding(
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
            return .disk(outerDiameter: 80, innerDiameter: 20, depth: 13)
        }
    }

    private func dimensionField(label: String, showUnits: Bool = false, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 40)

            if showUnits {
                Text("mm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
