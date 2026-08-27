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
                    .listRowInsets(EdgeInsets())
                    .padding()
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

            TextField(
                "Name",
                text: $stock.name
            )

            Picker(
                "Material",
                selection: $stock.material
            ) {
                ForEach(
                    StockMaterialType.allCases,
                    id: \.self
                ) { material in

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

            Picker(
                "Shape",
                selection: geometryTypeBinding
            ) {
                ForEach(
                    StockShape.allCases,
                    id: \.self
                ) { shape in

                    Text(shape.displayName)
                        .tag(shape)
                }
            }

            geometryFields
        }
    }

    var geometryTypeBinding: Binding<StockShape> {
        Binding(
            get: {
                stock.geometry.shape
            },
            set: { newShape in
                changeGeometry(to: newShape)
            }
        )
    }
}

private extension StockEditorView {

    func changeGeometry(to shape: StockShape) {

        switch shape {
            case .rectangular:
                stock.geometry = .rectangular(width: 100, height: 50, depth: 10)
            case .round:
                stock.geometry = .round(diameter: 20, depth: 100)
            case .disk:
                stock.geometry = .disk(outerDiameter: 30, innerDiameter: 20, depth: 100)
        }
    }
}

private extension StockEditorView {

    @ViewBuilder
    var geometryFields: some View {

        switch stock.geometry {

        case .rectangular(
            let width,
            let height,
            let depth
        ):
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

        case .round(
            let diameter,
            let depth
        ):
            MeasurementField(
                title: "Diameter",
                value: Binding(
                    get: { diameter },
                    set: {
                        stock.geometry = .round(
                            diameter: $0,
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
                        stock.geometry = .round(
                            diameter: diameter,
                            depth: $0
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
