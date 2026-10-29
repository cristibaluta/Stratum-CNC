//
//  StockEditorView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct StockEditorView: View {

    /// The draft being edited; owned by the sheet, which shows Revert/Save in its bottom bar.
    @Binding var draft: StockMaterial

    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            geometrySection
            generalSection
            availabilitySection
        }
        .formStyle(.grouped)
        .navigationTitle(draft.name)
    }
}

private extension StockEditorView {

    var generalSection: some View {
        Section("Material") {
            TextField("Name", text: $draft.name)

            Picker("Material", selection: $draft.material) {
                ForEach(StockMaterialType.allCases, id: \.self) { material in
                    Text(material.displayName)
                        .tag(material)
                }
            }
        }
    }


    var availabilitySection: some View {
        Section("Availability") {
            Stepper(value: $draft.quantity, in: 0...999) {
                HStack {
                    Text("Quantity")
                    Spacer()
                    TextField("Quantity", value: $draft.quantity, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
            }

            HStack {
                TextField("Link", text: linkBinding)
                Button {
                    if let url = draft.linkURL {
                        openURL(url)
                    }
                } label: {
                    Label("Buy", systemImage: "cart")
                }
                .disabled(draft.linkURL == nil)
            }
        }
    }

    var linkBinding: Binding<String> {
        Binding(
            get: { draft.link ?? "" },
            set: { draft.link = $0.isEmpty ? nil : $0 }
        )
    }
}

private extension StockEditorView {

    private var geometrySection: some View {
        Section("Geometry") {
            HStack {
                Form {
                    Picker("Shape", selection: geometryKindBinding) {
                        ForEach(StockGeometry.Kind.allCases) { kind in
                            Text(kind.displayName)
                                .tag(kind)
                        }
                    }
                    .frame(minWidth: 100, maxWidth: 180)

                    geometryFields
                }

                Divider()

                StockPreviewView(geometry: draft.geometry, material: draft.material)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 240)
        }
    }

    private var geometryKindBinding: Binding<StockGeometry.Kind> {
        Binding(
            get: {
                draft.geometry.kind
            },
            set: { newKind in
                draft.geometry = draft.geometry.converted(to: newKind)
            }
        )
    }

    @ViewBuilder
    private var geometryFields: some View {

        switch draft.geometry {

            case .rectangular(let width, let height, let depth):

                MeasurementField(title: "Width",
                                 value: Binding(
                                    get: { width },
                                    set: { draft.geometry = .rectangular(width: $0, height: height, depth: depth) }
                                 ),
                                 unit: "mm")

                MeasurementField(title: "Height",
                                 value: Binding(
                                    get: { height },
                                    set: { draft.geometry = .rectangular(width: width, height: $0, depth: depth) }
                                 ),
                                 unit: "mm")

                MeasurementField(title: "Depth",
                                 value: Binding(
                                    get: { depth },
                                    set: { draft.geometry = .rectangular(width: width, height: height, depth: $0) }
                                 ),
                                 unit: "mm")

            case .cylindrical(let diameter, let length):

                MeasurementField(title: "Diameter",
                                 value: Binding(
                                    get: { diameter },
                                    set: { draft.geometry = .cylindrical(diameter: $0, length: length) }
                                 ),
                                 unit: "mm")

                MeasurementField(title: "Length",
                                 value: Binding(
                                    get: { length },
                                    set: { draft.geometry = .cylindrical(diameter: diameter, length: $0) }
                                 ),
                                 unit: "mm")

            case .disk(let outerDiameter, let innerDiameter, let depth):

                MeasurementField(title: "Outer Diameter",
                                 value: Binding(
                                    get: { outerDiameter },
                                    set: { draft.geometry = .disk(outerDiameter: $0, innerDiameter: innerDiameter, depth: depth) }
                                 ),
                                 unit: "mm")

                MeasurementField(title: "Inner Diameter",
                                 value: Binding(
                                    get: { innerDiameter },
                                    set: { draft.geometry = .disk(outerDiameter: outerDiameter, innerDiameter: $0, depth: depth) }
                                 ),
                                 unit: "mm")

                MeasurementField(title: "Depth",
                                 value: Binding(
                                    get: { depth },
                                    set: { draft.geometry = .disk(outerDiameter: outerDiameter, innerDiameter: innerDiameter, depth: $0) }
                                 ),
                                 unit: "mm")
        }
    }
}
