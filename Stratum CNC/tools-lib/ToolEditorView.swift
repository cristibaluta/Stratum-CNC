//
//  ToolEditorView.swift
//  Stratum CNC
//
//  Restyled to match the reference "Tool Information" panel: a live
//  dimensioned diagram of the bit up top, and a clean label/value list
//  below instead of a plain metadata block.
//
//  Everything below assumes the same `Tool`, `ToolType`, `ToolMaterial`,
//  `ToolCuttingParameters`, `MeasurementField` and `OptionalMeasurementField`
//  types your project already has — only the visual layer changed. The one
//  new piece is `ToolDiagramView` (see ToolDiagramView.swift), which is
//  intentionally decoupled from your model so it can't collide with it.
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct ToolEditorView: View {
    @Binding var tool: Tool

    var body: some View {
        Form {
            geometrySection
            cuttingParametersSection
        }
        .formStyle(.grouped)
        .navigationTitle(tool.displayName)
    }
}

// MARK: - Diagram

private extension ToolEditorView {

    /// Live preview of the bit, redrawn as the geometry fields change —
    /// this is the CoreGraphics/Canvas piece standing in for the reference
    /// app's illustration with DS / LS / LC / DC callouts.
    var diagramSection: some View {
        ToolDiagramView(
            shankDiameter: tool.shankDiameter,
            toolDiameter: tool.toolDiameter,
            shoulderLength: shoulderLengthForDiagram,
            fluteLength: fluteLengthForDiagram,
            tipStyle: tipStyle(for: tool.type)
        )
        .frame(width: 100, height: 240)
        .listRowInsets(EdgeInsets())
    }

    /// `Tool` in the original file only exposes an optional overall
    /// `length`. The reference diagram distinguishes shoulder length (LS)
    /// from flute length (LC) separately — if your model already tracks
    /// those independently, swap this out for the real properties.
    var fluteLengthForDiagram: Double {
        guard let length = tool.length, length > 0 else { return 8 }
        return length * 0.6
    }

    var shoulderLengthForDiagram: Double {
        guard let length = tool.length, length > 0 else { return 6 }
        return max(length * 0.4, 3)
    }

    /// Maps your `ToolType` to how the tip should be drawn. Adjust the
    /// case names to whatever `ToolType` actually declares — these mirror
    /// the groups shown in the reference sidebar (Flat End, Ball Nose,
    /// Drill, Engraving/chamfer bits use the tool's tip angle).
    func tipStyle(for type: ToolType) -> ToolTipStyle {
        switch type {
        case .drill, .vBit, .chamfer, .engraving:
            return .conical(angleDegrees: tool.tipAngle ?? 90)
        case .ballNose:
            return .ball
        default:
            return .flat
        }
    }
}

// MARK: - Geometry

private extension ToolEditorView {

    var geometrySection: some View {
        Section {
            HStack {
                Form {
                    MeasurementField(title: "Shank Diameter (DS)", value: $tool.shankDiameter, unit: "mm")
                    MeasurementField(title: "Tool Diameter (DC)", value: $tool.toolDiameter, unit: "mm")
                    OptionalMeasurementField(title: "Length (L)", value: $tool.length, unit: "mm")

                    Picker("Type", selection: $tool.type) {
                        ForEach(ToolType.allCases, id: \.self) { type in
                            Text(type.displayName)
                                .tag(type)
                        }
                    }
                    .frame(minWidth: 100, maxWidth: 180)

                    if tool.tipAngle != nil {
                        MeasurementField(
                            title: "Tip Angle (TA)",
                            value: Binding(
                                get: { tool.tipAngle ?? 0 },
                                set: { tool.tipAngle = $0 }
                            ),
                            unit: "°"
                        )
                    }
                }
                Spacer()
                Divider()
                diagramSection
            }
        } header: {
            Text("Geometry")
        }
    }
}

// MARK: - Cutting Parameters

private extension ToolEditorView {

    var cuttingParametersSection: some View {
        Section {
            ToolParametersMatrix(tool: tool)
                .frame(maxWidth: .infinity)
//            Picker("Material", selection: $selectedMaterial) {
//                ForEach(availableMaterials, id: \.self) { material in
//                    Text(material.displayName)
//                        .tag(material)
//                }
//            }
//
//            if let parametersBinding = parametersBinding {
//                MeasurementField(
//                    title: "Spindle Speed",
//                    value: Binding(
//                        get: {
//                            Double(parametersBinding.wrappedValue.spindleRPM ?? 0)
//                        },
//                        set: {
//                            parametersBinding.wrappedValue.spindleRPM = Int($0)
//                        }
//                    ),
//                    unit: "RPM"
//                )
//
//                MeasurementField(
//                    title: "Feed Rate",
//                    value: Binding(
//                        get: {
//                            parametersBinding.wrappedValue.feedRate ?? 0
//                        },
//                        set: {
//                            parametersBinding.wrappedValue.feedRate = $0
//                        }
//                    ),
//                    unit: "mm/min"
//                )
//
//                MeasurementField(
//                    title: "Plunge Rate",
//                    value: Binding(
//                        get: {
//                            parametersBinding.wrappedValue.plungeFeedRate ?? 0
//                        },
//                        set: {
//                            parametersBinding.wrappedValue.plungeFeedRate = $0
//                        }
//                    ),
//                    unit: "mm/min"
//                )
//
//                MeasurementField(
//                    title: "Depth of Cut",
//                    value: Binding(
//                        get: {
//                            parametersBinding.wrappedValue.depthOfCut ?? 0
//                        },
//                        set: {
//                            parametersBinding.wrappedValue.depthOfCut = $0
//                        }
//                    ),
//                    unit: "mm"
//                )
//            } else {
//                ContentUnavailableView(
//                    "No Parameters",
//                    systemImage: "slider.horizontal.3",
//                    description: Text(
//                        "No cutting parameters are defined for \(selectedMaterial.displayName)."
//                    )
//                )
//            }
        } header: {
            Text("Cutting Parameters")
        }
    }

//    var parametersBinding: Binding<ToolCuttingParameters>? {
//        guard tool.parameters[selectedMaterial.rawValue] != nil else {
//            return nil
//        }
//
//        return Binding(
//            get: {
//                tool.parameters[selectedMaterial.rawValue]!
//            },
//            set: {
//                tool.parameters[selectedMaterial.rawValue] = $0
//            }
//        )
//    }
}

// MARK: - Metadata

private extension ToolEditorView {

    /// Reworked as a plain label/value list, monospaced values right
    /// aligned — same layout language as the reference "Tool Information"
    /// panel (Number, Type, Handle Diameter, Shoulder Length, Flute
    /// Length, Diameter).
    var metadataSection: some View {
        Section("Information") {
            if let group = tool.group {
                infoRow("Group", group)
            }
            infoRow("Type", tool.type.displayName)
            infoRow("ID", tool.id.uuidString, monospaced: true)
//            infoRow("Handle Diameter (DS)", formatted(tool.shankDiameter, unit: "mm"))
//            infoRow("Diameter (DC)", formatted(tool.toolDiameter, unit: "mm"))
//            if let length = tool.length {
//                infoRow("Length", formatted(length, unit: "mm"))
//            }
        }
    }

    func infoRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(monospaced ? .caption.monospaced() : .body)
                .foregroundStyle(.secondary)
        }
    }

    func formatted(_ value: Double, unit: String) -> String {
        let number = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.3f", value)
        return "\(number) \(unit)"
    }
}
