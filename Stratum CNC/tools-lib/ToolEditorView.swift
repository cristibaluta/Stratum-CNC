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
    @Environment(\.openURL) private var openURL

    /// Edits apply live (the list updates immediately); nothing is written to disk until Save.
    @Binding var tool: Tool

    var body: some View {
        Form {
            geometrySection
            cuttingParametersSection
            availabilitySection
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
        Section("Geometry") {
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
        }
    }
}

// MARK: - Cutting Parameters

private extension ToolEditorView {

    var cuttingParametersSection: some View {
        Section("Cutting Parameters") {
            ToolParametersMatrix(presets: $tool.presets)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Availability

private extension ToolEditorView {

    var availabilitySection: some View {
        Section("Availability") {
            Stepper(value: $tool.quantity, in: 0...9999) {
                HStack {
                    Text("Quantity")
                    Spacer()
                    TextField("Quantity", value: $tool.quantity, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
            }

            HStack {
                TextField("Link", text: linkBinding)
                Button {
                    if let url = tool.linkURL {
                        openURL(url)
                    }
                } label: {
                    Label("Buy", systemImage: "cart")
                }
                .disabled(tool.linkURL == nil)
            }
        }
    }

    var linkBinding: Binding<String> {
        Binding(
            get: { tool.link ?? "" },
            set: { tool.link = $0.isEmpty ? nil : $0 }
        )
    }
}
