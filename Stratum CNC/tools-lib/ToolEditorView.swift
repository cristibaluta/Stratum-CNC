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

    /// Where the tool came from, shown as a pill next to the name. Read-only.
    let source: ToolSourceInfo?

    var body: some View {
        let _ = Self._printChanges()
        Form {
            headerSection
            geometrySection
            cuttingParametersSection
            availabilitySection
        }
        .formStyle(.grouped)
        .navigationTitle(tool.displayName)
    }
}

// MARK: - Header

private extension ToolEditorView {

    /// The tool's name, editable (the list rows show the type, not the name), and its source.
    var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                TextField("Name", text: $tool.name, prompt: Text("Tool name"))
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .labelsHidden()

                if let source {
                    SourceChip(source: source)
                }
            }
        }
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

    /// The flute (LC) is the cutting height.
    var fluteLengthForDiagram: Double {
        guard let height = tool.cuttingHeight, height > 0 else { return 8 }
        return height
    }

    /// The shoulder (LS) is what is left of the tool length above the flute. Without a tool
    /// length to measure it from, it is drawn at two thirds of the flute, so the picture still
    /// looks like a tool.
    var shoulderLengthForDiagram: Double {
        let flute = fluteLengthForDiagram
        if let length = tool.toolLength, length > flute {
            return length - flute
        }
        return max(flute * 0.67, 3)
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
                    Picker("Type", selection: $tool.type) {
                        ForEach(ToolType.allCases, id: \.self) { type in
                            Text(type.displayName)
                                .tag(type)
                        }
                    }
                    .frame(minWidth: 100, maxWidth: 180)

//                    Picker("Cutting Direction", selection: $tool.cuttingDirection) {
//                        Text("Not set")
//                            .tag(CuttingDirection?.none)
//                        ForEach(CuttingDirection.allCases, id: \.self) { direction in
//                            Text(direction.displayName)
//                                .tag(CuttingDirection?.some(direction))
//                        }
//                    }
//                    .frame(minWidth: 100, maxWidth: 220)

                    OptionalCountField(title: "Number of Flutes", value: $tool.numberOfFlutes)

                    MeasurementField(title: "Shank Diameter (DS)", value: $tool.shankDiameter, unit: "mm")
                    MeasurementField(title: "Tool Diameter (DC)", value: $tool.toolDiameter, unit: "mm")
                    OptionalMeasurementField(title: "Cutting Height (H)", value: $tool.cuttingHeight, unit: "mm")
                    OptionalMeasurementField(title: "Tool Length", value: $tool.toolLength, unit: "mm")

                    typeSpecificFields
                }

                Spacer()
                Divider()

                diagramSection
            }
        }
    }
}

// MARK: - Fields that only some tools have

private extension ToolEditorView {

    @ViewBuilder
    var typeSpecificFields: some View {
        if tool.type.hasTipAngle || tool.tipAngle != nil {
            OptionalMeasurementField(title: "Tip Angle (TA)", value: $tool.tipAngle, unit: "°")
        }

        if tool.type.hasTipDiameter || tool.tipDiameter != nil {
            OptionalMeasurementField(title: "Tip Diameter", value: $tool.tipDiameter, unit: "mm")
        }

        if tool.type.hasCornerRadius || tool.cornerRadius != nil {
            OptionalMeasurementField(title: "Corner Radius", value: $tool.cornerRadius, unit: "mm")
        }

        if tool.type == .threadMill {
            MeasurementField(title: "Min Pitch", value: thread.minPitch, unit: "mm")
            MeasurementField(title: "Max Pitch", value: thread.maxPitch, unit: "mm")
            MeasurementField(title: "Thread Profile Angle", value: thread.profileAngle, unit: "°")
            OptionalCountField(
                title: "Thread Teeth",
                value: Binding(
                    get: { thread.wrappedValue.teeth },
                    set: { thread.wrappedValue.teeth = $0 ?? 1 }
                )
            )
        }
    }

    /// The thread mill's thread values, editable even before the tool has any (they start at the defaults).
    var thread: Binding<ThreadProfile> {
        Binding(
            get: { tool.thread ?? ThreadProfile() },
            set: { tool.thread = $0 }
        )
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
