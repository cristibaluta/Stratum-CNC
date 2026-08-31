//
//  StockEditorView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct StockEditorView: View {

    @Binding var stock: StockMaterial

    var body: some View {
        Form {
            Section {
                StockPreviewView(geometry: stock.geometry, material: stock.material)
                    .frame(height: 200)
            }
            generalSection
            geometrySection
        }
        .formStyle(.grouped)
        .navigationTitle(stock.name)
    }
}

private extension StockEditorView {

    var generalSection: some View {
        Section("Material") {
            TextField("Name", text: $stock.name)

            Picker("Material", selection: $stock.material) {
                ForEach(StockMaterialType.allCases, id: \.self) { material in
                    Text(material.displayName)
                        .tag(material)
                }
            }
        }
    }
}

private extension StockEditorView {

    var geometrySection: some View {
        Section("Geometry") {
            Picker("Shape", selection: geometryTypeBinding) {
                ForEach(StockGeometry.allCases, id: \.self) { shape in
                    Text(shape.displayName)
                        .tag(shape)
                }
            }
            geometryFields
        }
    }

    var geometryTypeBinding: Binding<StockGeometry> {
        Binding(
            get: {
                stock.geometry
            },
            set: { newShape in
                changeGeometry(to: newShape)
            }
        )
    }
}

private extension StockEditorView {

    func changeGeometry(to shape: StockGeometry) {
        stock.geometry = shape
    }
}

private extension StockEditorView {

    @ViewBuilder
    var geometryFields: some View {

        switch stock.geometry {

        case .rectangular(let width, let height, let depth):
            MeasurementField(
                title: "Width",
                value: Binding(
                    get: { width },
                    set: {
                        stock.geometry = .rectangular(
                            width: $0,
                            height: height,
                            depth: depth
                        )
                    }
                ),
                unit: "mm"
            )

            MeasurementField(
                title: "Height",
                value: Binding(
                    get: { height },
                    set: {
                        stock.geometry = .rectangular(
                            width: width,
                            height: $0,
                            depth: depth
                        )
                    }
                ),
                unit: "mm"
            )

            MeasurementField(
                title: "Depth",
                value: Binding(
                    get: { depth },
                    set: {
                        stock.geometry = .rectangular(
                            width: width,
                            height: height,
                            depth: $0
                        )
                    }
                ),
                unit: "mm"
            )

        case .cylindrical(let diameter, let length):
            MeasurementField(
                title: "Diameter",
                value: Binding(
                    get: { diameter },
                    set: {
                        stock.geometry = .cylindrical(
                            diameter: $0,
                            length: length
                        )
                    }
                ),
                unit: "mm"
            )

            MeasurementField(
                title: "Length",
                value: Binding(
                    get: { length },
                    set: {
                        stock.geometry = .cylindrical(
                            diameter: diameter,
                            length: $0
                        )
                    }
                ),
                unit: "mm"
            )

        case .disk(let outerDiameter, let innerDiameter, let depth):
            MeasurementField(
                title: "Outer Diameter",
                value: Binding(
                    get: { outerDiameter },
                    set: {
                        stock.geometry = .disk(outerDiameter: $0, innerDiameter: innerDiameter, depth: depth)
                    }
                ),
                unit: "mm"
            )

            MeasurementField(
                title: "Inner Diameter",
                value: Binding(
                    get: { innerDiameter },
                    set: {
                        stock.geometry = .disk(outerDiameter: outerDiameter, innerDiameter: $0, depth: depth)
                    }
                ),
                unit: "mm"
            )

            MeasurementField(
                title: "Depth",
                value: Binding(
                    get: { depth },
                    set: {
                        stock.geometry = .disk(outerDiameter: outerDiameter, innerDiameter: innerDiameter, depth: $0)
                    }
                ),
                unit: "mm"
            )
        }
    }
}
