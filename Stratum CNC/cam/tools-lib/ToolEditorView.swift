//
//  ToolEditorView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct ToolEditorView: View {
    @Binding var tool: Tool

    @State private var selectedMaterial: ToolMaterial = .aluminum

    var body: some View {
        Form {
            geometrySection
            cuttingParametersSection
            metadataSection
        }
        .formStyle(.grouped)
        .navigationTitle(tool.displayName)
        .onAppear {
            selectFirstAvailableMaterial()
        }
        .onChange(of: tool.parameters) {
            if tool.parameters[selectedMaterial.rawValue] == nil {
                selectFirstAvailableMaterial()
            }
        }
    }
}

// MARK: - Geometry

private extension ToolEditorView {

    var geometrySection: some View {
        Section("Geometry") {
            MeasurementField(
                title: "Shank Diameter",
                value: $tool.shankDiameter,
                unit: "mm"
            )

            MeasurementField(
                title: "Tool Diameter",
                value: $tool.toolDiameter,
                unit: "mm"
            )

            OptionalMeasurementField(
                title: "Length",
                value: $tool.length,
                unit: "mm"
            )

            Picker("Type", selection: $tool.type) {
                ForEach(ToolType.allCases, id: \.self) { type in
                    Text(type.displayName)
                        .tag(type)
                }
            }

            if tool.tipAngle != nil {
                MeasurementField(
                    title: "Tip Angle",
                    value: Binding(
                        get: { tool.tipAngle ?? 0 },
                        set: { tool.tipAngle = $0 }
                    ),
                    unit: "°"
                )
            }
        }
    }
}

// MARK: - Cutting Parameters

private extension ToolEditorView {

    var cuttingParametersSection: some View {
        Section {
            Picker("Material", selection: $selectedMaterial) {
                ForEach(availableMaterials, id: \.self) { material in
                    Text(material.displayName)
                        .tag(material)
                }
            }

            if let parametersBinding = parametersBinding {
                MeasurementField(
                    title: "Spindle Speed",
                    value: Binding(
                        get: {
                            Double(parametersBinding.wrappedValue.spindleRPM ?? 0)
                        },
                        set: {
                            parametersBinding.wrappedValue.spindleRPM = Int($0)
                        }
                    ),
                    unit: "RPM"
                )

                MeasurementField(
                    title: "Feed Rate",
                    value: Binding(
                        get: {
                            parametersBinding.wrappedValue.feedRate ?? 0
                        },
                        set: {
                            parametersBinding.wrappedValue.feedRate = $0
                        }
                    ),
                    unit: "mm/min"
                )

                MeasurementField(
                    title: "Plunge Rate",
                    value: Binding(
                        get: {
                            parametersBinding.wrappedValue.plungeFeedRate ?? 0
                        },
                        set: {
                            parametersBinding.wrappedValue.plungeFeedRate = $0
                        }
                    ),
                    unit: "mm/min"
                )

                MeasurementField(
                    title: "Depth of Cut",
                    value: Binding(
                        get: {
                            parametersBinding.wrappedValue.depthOfCut ?? 0
                        },
                        set: {
                            parametersBinding.wrappedValue.depthOfCut = $0
                        }
                    ),
                    unit: "mm"
                )
            } else {
                ContentUnavailableView(
                    "No Parameters",
                    systemImage: "slider.horizontal.3",
                    description: Text(
                        "No cutting parameters are defined for \(selectedMaterial.displayName)."
                    )
                )
            }
        } header: {
            Text("Cutting Parameters")
        }
    }

    var availableMaterials: [ToolMaterial] {
        ToolMaterial.allCases
//            .filter {
//            ToolMaterial(rawValue: tool.parameters.keys) != nil
//        }
    }

    var parametersBinding: Binding<ToolCuttingParameters>? {
        guard tool.parameters[selectedMaterial.rawValue] != nil else {
            return nil
        }

        return Binding(
            get: {
                tool.parameters[selectedMaterial.rawValue]!
            },
            set: {
                tool.parameters[selectedMaterial.rawValue] = $0
            }
        )
    }

    func selectFirstAvailableMaterial() {
        if let first = availableMaterials.first {
            selectedMaterial = first
        }
    }
}

// MARK: - Metadata

private extension ToolEditorView {

    var metadataSection: some View {
        Section("Information") {
            if let group = tool.group {
                LabeledContent("Group") {
                    Text(group)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("ID") {
                Text(tool.id.uuidString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
