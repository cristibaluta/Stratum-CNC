//
//  PanelToolpathDetails.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 14.10.2026.
//

import SwiftUI
import StratumCAM

struct PanelToolpathDetails: View {
    @Binding var toolpath: ToolpathData

    /// The stock being cut, used to choose the tool's preset when a tool is picked.
    var stockMaterial: StockMaterialType

    /// The stock's size along Z (mm), for the "Through stock" End Z helper. `nil` hides it.
    var stockThickness: Double? = nil

    /// Every other toolpath's current name, so the auto-generated name for this
    /// one  picks a number that isn't already taken.
    var siblingNames: Set<String> = []

    /// True while the canvas is picking shapes for this toolpath. That's the case
    /// whenever the cell is open: clicking a shape on the canvas adds/removes it.
    var isPicking: Bool = false

    /// Result of the last Generate for this toolpath, if any.
    var generation: ToolpathGeneration? = nil
    /// True while the generation is running in the background.
    var isGenerating: Bool = false
    /// Builds the toolpaths from the selected shapes.
    var onGenerate: () -> Void = {}
    var onScrub: (Int) -> Void = { _ in }
    var onDone: () -> Void = {}
    var onDelete: () -> Void = {}
    /// Adds another toolpath after this one and opens it.
    var onAddNext: () -> Void = {}
    /// The outlines of the selected shapes in world space, one per shape, for drawings in the
    /// panel (where the holding tabs sit). Called only when a drawing is shown.
    var targetShapes: () -> [CGPath] = { [] }

    @StateObject private var model = ToolpathDetailsModel()

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                rowHeader
                    .padding(.bottom, 10)

                InspectorSection(title: "Shapes") {
                    rowShapes
                }
                InspectorSection(title: "Operation") {
                    rowOperation
                    rowOperationOptions
                }
                InspectorSection(title: "Tool & feeds") {
                    rowTool
                }
                // How the tool moves in the plane
                InspectorSection(title: "XY movement") {
                    rowXYMovement
                }
                // Start Z, End Z, the depth per pass, how the tool enters the material and the clearance height.
                InspectorSection(title: "Z levels") {
                    rowDepth
                }
                InspectorSection(title: "Preview") {
                    rowPreview
                    rowScrub
                }
                rowBottomBar
            }
            .padding(8)
            .onChange(of: toolpath.id) { _, _ in
                model.reset()
            }
            // A new Generate starts its preview from the end again, like the canvas does
            .onChange(of: generation?.id) { _, _ in model.resetScrub() }
        }
    }

    // MARK: Generate

    @ViewBuilder
    private var rowHeader: some View {
        HStack(spacing: 8) {
            OperationIcon(kind: toolpath.operation.kind, size: 16)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            // Typing here is what makes a name "custom" -- from then on it stops
            // following the operation (see `operationKindBinding`).
            TextField("", text: model.nameBinding($toolpath))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .background(.background)
        }
    }

    @ViewBuilder
    private var rowOperation: some View {
        OperationPicker(kind: model.operationKindBinding($toolpath, siblingNames: siblingNames))
    }

    /// Which of the general fields (End Z, Stepdown, Stepover) the operation reads.
    private var requirements: SC.OperationRequirements {
        model.requirements(for: toolpath)
    }

    @ViewBuilder
    private var rowOperationOptions: some View {
        // Side, direction, diameters… whatever SC.MachiningOperation.formFields
        // defines for the chosen operation, plus the holding tabs and the clearing pattern.
        OperationOptionsView(toolpath: $toolpath, targetShapes: targetShapes, part: .operation)
    }

    @ViewBuilder
    private var rowXYMovement: some View {
        OperationOptionsView(toolpath: $toolpath, targetShapes: targetShapes, part: .xyMovement)
    }

    @ViewBuilder
    private var rowTool: some View {
        ToolPicker(tool: $toolpath.tool, onToolPicked: { tool in
            model.applyPreset(of: tool, to: $toolpath, stockMaterial: stockMaterial)
        })
        // A tool the operation can't use, flagged here instead of failing at Preview
        if let warning = toolpath.toolCompatibilityWarning {
            InspectorNote(text: warning, isWarning: true)
        }
        if let presetNote = model.presetNote {
            InspectorNote(text: presetNote)
        }
        InspectorIntField(title: "Spindle", value: $toolpath.spindleRPM, suffix: "rpm")
    }

    @ViewBuilder
    private var rowDepth: some View {
        // Z range (a counterbore has its own depth instead of an End Z; it is shown as one)
        InspectorNumberField(title: "Start Z", value: $toolpath.startZ, suffix: "mm")
        if toolpath.operation.kind == .counterbore {
            InspectorNumberField(title: "End Z", value: model.counterboreEndDepth($toolpath), suffix: "mm", prefix: "−")
                .help("How deep the counterbore goes below the top of the stock.")
        } else if requirements.usesEndZ {
            InspectorNumberField(title: "End Z", value: model.editedBinding(model.endDepth($toolpath), .endZ, in: $toolpath), suffix: "mm", prefix: "−") {
                if model.isHoleOperation(toolpath), let thickness = stockThickness, thickness > 0 {
                    throughStockButton(thickness: thickness)
                }
            }
            .help(model.endZHelp)
        }
        // How much is cut per pass: the same idea under the name each operation gives it. A slot
        // steps down by its own depth per pass (not the general stepdown, see `rampingButton`),
        // a drill by its peck depth.
        if toolpath.operation.kind == .slotting {
            InspectorNumberField(title: "Depth per pass", value: model.slotDepthPerPass($toolpath), suffix: "mm")
        } else if requirements.usesStepdown {
            InspectorNumberField(title: "Stepdown", value: model.editedBinding($toolpath.stepDown, .stepDown, in: $toolpath), suffix: "mm")
        }
        if toolpath.operation.kind == .drilling {
            ToggleField(title: "Peck drilling",
                        isOn: $toolpath.operation.drillUsesPecking,
                        help: "Drill in steps of the peck depth, retracting in between to clear the chips.")
            if toolpath.operation.drillUsesPecking {
                InspectorNumberField(title: "Peck depth", value: model.drillPeckDepth($toolpath), suffix: "mm")
            }
        }
        // How the tool gets down into the material: ramp, helix or plunge.
        if OperationOptionsView.hasEntry(for: toolpath) {
            OperationOptionsView(toolpath: $toolpath, part: .entry)
        }
        // Always available, also for operations without an entry strategy (drill, bore…)
        InspectorNumberField(title: "Ramp feed", value: $toolpath.plungeRate, suffix: "mm/min")
            .help(model.plungeFeedHelp(for: toolpath))
        // Holding tabs (contour): material left standing at the bottom of the cut
        if OperationOptionsView.hasTabs(for: toolpath) {
            OperationOptionsView(toolpath: $toolpath, targetShapes: targetShapes, part: .tabs)
        }
        InspectorNumberField(title: "Clearance Z", value: $toolpath.safeZ, suffix: "mm")
            .help("The height the tool travels at between cuts.")
    }

    private func throughStockButton(thickness: Double) -> some View {
        Button {
            model.applyThroughStock(to: $toolpath, thickness: thickness)
        } label: {
            Label("Through stock", systemImage: "arrow.down.to.line")
                .font(.system(size: 11))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.isThroughStock(toolpath, thickness: thickness))
        .help(model.throughStockHelp(thickness: thickness))
    }

    /// How many shapes the toolpath cuts. Shapes are chosen by clicking them on
    /// the canvas while the cell is open, so there's nothing to press here.
    @ViewBuilder
    private var rowShapes: some View {
        // Facing can cover the whole stock instead of the selected shapes
        if toolpath.operation.kind == .facing {
            InspectorRow(label: "Area") {
                Picker("", selection: $toolpath.operation.facingWholeStock) {
                    Text("Selection").tag(false)
                    Text("Whole stock").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Face the bounding box of the selected shapes, or the whole stock")
            }
        }
        InspectorRow(label: "Selected") {
            shapesLabel
        }
        // What to click on the canvas for this operation (the slot's text follows its source)
        if let hint = toolpath.operation.kind.selectionHint(slotSource: toolpath.operation.slotSource) {
            InspectorNote(text: hint)
        }
    }

    /// Generation status on the left, the Preview button on the right. Preview builds the
    /// toolpath from the selected shapes and shows it on the canvas.
    @ViewBuilder
    private var rowPreview: some View {
        // Only offered once there is something to cut
        if !toolpath.hasGeometry {
            InspectorNote(text: "Select shapes to preview the toolpath.", isIndented: false)
        } else {
          VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            HStack(alignment: .center, spacing: 8) {
                generationStatus
                Spacer(minLength: 0)
                Button {
                    onGenerate()
                } label: {
                    if isGenerating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating…")
                                .font(.system(size: 12, weight: .medium))
                        }
                    } else {
                        Label("Preview", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isGenerating || toolpath.leadInConflictsWithEntry)
                .help(model.previewButtonHelp(for: toolpath))
            }
            // Warnings don't stop the toolpath, and only matter while the result is current
            if let generation, generation.isCurrent(for: toolpath) {
                ForEach(generation.warningMessages, id: \.self) { message in
                    InspectorNote(text: message, isWarning: true, isIndented: false)
                }
                // The canvas draws one pass per toolpath; say so, so the other passes aren't
                // mistaken for missing.
                if generation.errorMessage == nil, generation.maxPassesPerToolpath > 1 {
                    InspectorNote(text: model.multiPassNote(for: generation), isIndented: false)
                }
            }
          }
        }
    }

    /// The bottom bar: delete on the left; add the next toolpath and close on the right.
    /// Closing is the last step after previewing; Esc does the same.
    private var rowBottomBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Delete this toolpath")

                Spacer()

                Button {
                    onAddNext()
                } label: {
                    Label("Next toolpath", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Add another toolpath")

                doneButton
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var generationStatus: some View {
        if let generation {
            if let message = generation.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.trailing)
            } else if !generation.isCurrent(for: toolpath) {
                Label("Outdated...", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.trailing)
            } else {
                Label(model.successText(for: generation), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// Previews the generated toolpath on the canvas: only this toolpath is shown, drawn up
    /// to the slider with the cutter at that point. One step is one move of the toolpath,
    /// like one line in the controller's G-code slider. Only offered while the result
    /// matches the settings (see `CAMModel.scrubbableGeneration`).
    @ViewBuilder
    private var rowScrub: some View {
        if let generation,
           generation.isCurrent(for: toolpath),
           let scrub = generation.scrub,
           scrub.stepCount > 0 {

            let total = scrub.stepCount
            HStack(spacing: 10) {
                Slider(value: model.scrubBinding(total: total, onScrub: onScrub), in: 0...Double(total))
                    .controlSize(.small)

                Text(model.scrubLabel(total: total))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .help("Scrub through the generated toolpath")
        }
    }

    // MARK: Shapes

    /// How many shapes the toolpath cuts. Shapes are chosen by clicking them on
    /// the canvas while the cell is open, so there's nothing to press here.
    private var shapesLabel: some View {
        Label(model.shapesTitle(for: toolpath), systemImage: "cursorarrow.click")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(toolpath.hasGeometry ? Color.secondary : Color.orange)
            .help("Click shapes on the canvas to add or remove them")
    }

    /// Esc does the same.
    private var doneButton: some View {
        Button("Done") {
            onDone()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut(.cancelAction)
        .help("Close the toolpath (Esc)")
    }
}
