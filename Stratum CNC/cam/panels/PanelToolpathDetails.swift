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
    /// A rest toolpath only: the pocket it is linked to, nil when that one is gone.
    var restSource: ToolpathData? = nil
    /// Draw the corners a pocket's tool couldn't reach on the canvas.
    var showsRestAreas: Binding<Bool> = .constant(true)
    /// Adds a rest toolpath after this pocket and opens it.
    var onCreateRest: () -> Void = {}
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

    /// The title section's compact form is showing. Remembered like the other sections'.
    @AppStorage("inspector.sectionCollapsed.Title") private var isTitleCollapsed = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                // The title, the operation it does and what that operation does. The title row
                // is the same either way; collapsed, what is under it shrinks: the operation
                // picker without its label or summary, and a thread mill's standard thread
                // and radial passes in one row.
                VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
                    rowHeader
                    if isTitleCollapsed {
                        // One line, like the other sections' compact forms
                        HStack(spacing: 6) {
                            OperationPicker(kind: model.operationKindBinding($toolpath, siblingNames: siblingNames),
                                            isCompact: true)
                                // A rest operation is created from a pocket and stays one.
                                .disabled(toolpath.operation.kind == .restMachining)
                            if OperationOptionsView.hasOperationFields(for: toolpath) {
                                OperationOptionsView(toolpath: $toolpath, part: .operationCompact)
                            }
                        }
                    } else {
                        rowOperation
                        InspectorNote(text: toolpath.operation.kind.summary)
                        // The operation's own settings, right under its type: a thread's standard
                        // and pitch, a bore's diameter, a chamfer's width…
                        if OperationOptionsView.hasOperationFields(for: toolpath) {
                            OperationOptionsView(toolpath: $toolpath, part: .operation)
                        }
                    }
                }
                .padding(.bottom, 12)

                InspectorSection {
                    rowShapes
                }
                InspectorSection(title: "Tool", collapsible: true, compact: {
                    rowToolCompact
                }) {
                    rowTool
                }
                // How the tool moves in the plane
                InspectorSection(title: "XY plane", collapsible: true, compact: {
                    OperationOptionsView(toolpath: $toolpath, part: .xyCompact)
                }) {
                    rowXYMovement
                }
                // Start Z, End Z, the depth per pass, the holding tabs, and the Safe and Retract heights.
                InspectorSection(title: "Z axis", collapsible: true, compact: {
                    rowDepthCompact
                }) {
                    rowDepth
                }
                // How the tool gets into the cut: ramp or helix, the feed going down, lead-in/out
                InspectorSection(title: "Entry", collapsible: true, compact: {
                    rowEntryCompact
                }) {
                    rowEntry
                }
                InspectorSection(title: "Preview", collapsible: true) {
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

            // The name is reset to the operation's auto name whenever the operation is
            // changed (see `operationKindBinding`), and is free text otherwise.
            TextField("", text: model.nameBinding($toolpath))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .background(.background)
                // A field being edited ignores outside changes to its text; a new
                // identity per operation makes it show the renamed title.
                .id(toolpath.operation.kind)

            // As tall as the name, so the title row keeps its height
            InspectorDisclosureButton(title: "Toolpath", isExpanded: !isTitleCollapsed, height: 22) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isTitleCollapsed.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private var rowOperation: some View {
        OperationPicker(kind: model.operationKindBinding($toolpath, siblingNames: siblingNames))
            // A rest operation is created from a pocket and stays one.
            .disabled(toolpath.operation.kind == .restMachining)
    }

    /// Which of the general fields (End Z, Stepdown, Stepover) the operation reads.
    private var requirements: SC.OperationRequirements {
        model.requirements(for: toolpath)
    }

    @ViewBuilder
    private var rowXYMovement: some View {
        OperationOptionsView(toolpath: $toolpath, targetShapes: targetShapes, part: .xyMovement)
    }

    @ViewBuilder
    private var rowTool: some View {
        ToolPicker(tool: $toolpath.tool, stockMaterial: stockMaterial, onToolPicked: { tool in
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

    /// The Tool section's collapsed form: the tool, the library and the spindle speed in one
    /// row. The notes of the full form become help texts, and a tool the operation can't use
    /// shows as a warning icon.
    @ViewBuilder
    private var rowToolCompact: some View {
        HStack(spacing: 6) {
            ToolPicker(tool: $toolpath.tool, style: .compact, stockMaterial: stockMaterial, extraHelp: model.presetNote, onToolPicked: { tool in
                model.applyPreset(of: tool, to: $toolpath, stockMaterial: stockMaterial)
            })
            InspectorIntField(title: "Spindle speed (rpm)", value: $toolpath.spindleRPM, suffix: "rpm", isCompact: true)
            if let warning = toolpath.toolCompatibilityWarning {
                InspectorWarningButton(message: warning)
            }
        }
    }

    /// The ramp or helix, the feed going down and, for a contour, the lead-in and lead-out.
    @ViewBuilder
    private var rowEntry: some View {
        InspectorNumberField(title: "Entry Z", value: $toolpath.entryZ, suffix: "mm")
            .help("Height above the stock where the entry starts. The tool rapids down to here, then feeds in and the entry strategy (plunge, ramp or helix) is applied.")
        // How the tool gets down into the material: ramp, helix or plunge.
        if OperationOptionsView.hasEntry(for: toolpath) {
            OperationOptionsView(toolpath: $toolpath, part: .entry)
        }
        // Always available, also for operations without an entry strategy (drill, bore…)
        InspectorNumberField(title: "Entry feed", value: $toolpath.plungeRate, suffix: "mm/min")
            .help(model.plungeFeedHelp(for: toolpath))
        if OperationOptionsView.hasLeadInOut(for: toolpath) {
            OperationOptionsView(toolpath: $toolpath, part: .leadInOut)
        }
    }

    @ViewBuilder
    private var rowDepth: some View {
        // Z range (a counterbore has its own depth instead of an End Z; it is shown as one)
        InspectorNumberField(title: "Start Z", value: $toolpath.startZ, suffix: "mm")
            .help("The height where cutting starts. 0 is the top of the stock; passes above it are skipped.")
        if toolpath.operation.kind == .counterbore {
            InspectorNumberField(title: "End Z", value: model.counterboreEndDepth($toolpath), suffix: "mm", prefix: "−")
                .help("How deep the counterbore goes below the top of the stock.")
        } else if requirements.usesEndZ {
            InspectorNumberField(title: "End Z", value: model.editedBinding(model.endDepth($toolpath), .endZ, in: $toolpath), suffix: "mm", prefix: "−") {
                if model.offersThroughStock(toolpath), let thickness = stockThickness, thickness > 0 {
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
                .help("How deep the slot is cut in each pass.")
            passesNote(stepdown: toolpath.operation.slotDepthPerPass)
        } else if requirements.usesStepdown {
            InspectorNumberField(title: "Stepdown", value: model.editedBinding($toolpath.stepDown, .stepDown, in: $toolpath), suffix: "mm")
                .help("How deep the tool cuts in each pass. Smaller means lighter cuts and more passes.")
            passesNote(stepdown: toolpath.stepDown)
        }
        if toolpath.operation.kind == .drilling {
            ToggleField(title: "Peck drilling",
                        isOn: $toolpath.operation.drillUsesPecking,
                        help: "Drill in steps of the peck depth, retracting in between to clear the chips.")
            if toolpath.operation.drillUsesPecking {
                InspectorNumberField(title: "Peck depth", value: model.drillPeckDepth($toolpath), suffix: "mm")
                    .help("How deep the drill goes before retracting to clear the chips.")
            }
        }
        // The operation's own depth settings: a bore's dwell and retract, a chamfer's depth
        if OperationOptionsView.hasDepthFields(for: toolpath) {
            OperationOptionsView(toolpath: $toolpath, part: .depth)
        }
        // Holding tabs (contour): material left standing at the bottom of the cut
        if OperationOptionsView.hasTabs(for: toolpath) {
            OperationOptionsView(toolpath: $toolpath, targetShapes: targetShapes, part: .tabs)
        }
        InspectorNumberField(title: "Safe Z", value: $toolpath.safeZ, suffix: "mm")
            .help("The height the tool starts and ends at, and travels at between distant cuts.")
        InspectorNumberField(title: "Retract Z", value: $toolpath.retractZ, suffix: "mm")
            .help("The height the tool lifts to between passes. Not higher than Safe Z.")
    }

    /// The Z axis section's collapsed form: where the cut starts and ends and how deep each
    /// pass goes, then the Safe Z. Retract Z, the holding tabs and the operation's own
    /// depth settings are in the full section only.
    @ViewBuilder
    private var rowDepthCompact: some View {
        let isSlot = toolpath.operation.kind == .slotting
        let stepdown = isSlot ? toolpath.operation.slotDepthPerPass : toolpath.stepDown
        let passes = model.passesNote(for: toolpath, stepdown: stepdown)

        HStack(spacing: 6) {
            InspectorCompactNumberField(tag: "Start", value: $toolpath.startZ,
                                        help: "Start Z (mm): the height where cutting starts. 0 is the top of the stock.")
            if toolpath.operation.kind == .counterbore {
                InspectorCompactNumberField(tag: "End", value: model.counterboreEndDepth($toolpath), prefix: "−",
                                            help: "End Z (mm): how deep the counterbore goes below the top of the stock.")
            } else if requirements.usesEndZ {
                InspectorCompactNumberField(tag: "End", value: model.editedBinding(model.endDepth($toolpath), .endZ, in: $toolpath), prefix: "−",
                                            help: "End Z (mm): \(model.endZHelp)")
            }
            if isSlot {
                InspectorCompactNumberField(tag: "Step", value: model.slotDepthPerPass($toolpath),
                                            help: "Depth per pass (mm). \(passes?.text ?? "")")
            } else if requirements.usesStepdown {
                InspectorCompactNumberField(tag: "Step", value: model.editedBinding($toolpath.stepDown, .stepDown, in: $toolpath),
                                            help: "Stepdown (mm): how deep the tool cuts in each pass. \(passes?.text ?? "")")
            }
            if toolpath.operation.kind == .drilling, toolpath.operation.drillUsesPecking {
                InspectorCompactNumberField(tag: "Peck", value: model.drillPeckDepth($toolpath),
                                            help: "Peck depth (mm): how deep the drill goes before retracting.")
            }
            InspectorCompactNumberField(tag: "Safe", value: $toolpath.safeZ,
                                        help: "Safe Z (mm): the height the tool starts and ends at, and travels at between distant cuts.")
            if let passes, passes.isWarning {
                InspectorWarningButton(message: passes.text)
            }
        }
    }

    /// The Entry section's collapsed form: the strategy, its angle, the feed going down and
    /// the Entry Z. The lead-in and lead-out are in the full section only.
    @ViewBuilder
    private var rowEntryCompact: some View {
        HStack(spacing: 6) {
            if OperationOptionsView.hasEntry(for: toolpath) {
                OperationOptionsView(toolpath: $toolpath, part: .entryCompact)
            }
            InspectorCompactNumberField(tag: "Feed", value: $toolpath.plungeRate,
                                        help: "Entry feed (mm/min). \(model.plungeFeedHelp(for: toolpath))")
            InspectorCompactNumberField(tag: "Entry Z", value: $toolpath.entryZ,
                                        help: "Entry Z (mm): height above the stock where the entry starts. The tool rapids down to here, then feeds in.")
        }
    }

    /// How many passes Start Z, End Z and the stepdown come to, under the field that sets it.
    @ViewBuilder
    private func passesNote(stepdown: Double) -> some View {
        if let note = model.passesNote(for: toolpath, stepdown: stepdown) {
            InspectorNote(text: note.text, isWarning: note.isWarning)
        }
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
        .help(model.throughStockHelp(for: toolpath, thickness: thickness))
    }

    /// How many shapes the toolpath cuts. Shapes are chosen by clicking them on
    /// the canvas while the cell is open, so there's nothing to press here.
    @ViewBuilder
    private var rowShapes: some View {
        // A rest toolpath has no shapes of its own: it cuts the corners of its pocket
        if toolpath.operation.kind == .restMachining {
            InspectorRow(label: "Source") {
                Label(restSource?.name ?? "Source missing", systemImage: "link")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(restSource == nil ? Color.orange : Color.secondary)
                    .help("The pocket whose corners this operation cuts")
            }
            if let restSource, toolpath.tool.toolDiameter >= restSource.tool.toolDiameter {
                InspectorNote(text: "The tool has to be smaller than the pocket's tool (Ø\(restSource.tool.toolDiameter) mm) to reach its corners.",
                              isWarning: true)
            }
        } else {
            shapePickingRows
        }
    }

    @ViewBuilder
    private var shapePickingRows: some View {
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
        // A slot's selection is its outline or the line the tool centre follows
        if toolpath.operation.kind == .slotting {
            OperationOptionsView(toolpath: $toolpath, part: .shapes)
        }
        InspectorRow(label: "Selected") {
            shapesLabel
        }
    }

    /// Generation status on the left, the Preview button on the right. Preview builds the
    /// toolpath from the selected shapes and shows it on the canvas.
    @ViewBuilder
    private var rowPreview: some View {
        // Without shapes the button is there but disabled; what to do about it is said once,
        // in orange, under Shapes (see `shapesLabel`).
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
                .disabled(isGenerating || !toolpath.hasGeometry)
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
                // The corners this pocket's tool couldn't reach: offer to clean them with a smaller tool
                if toolpath.operation.kind == .pocket, generation.errorMessage == nil, !generation.restCorners.isEmpty {
                    restAreasRows(cornerCount: generation.restCorners.count)
                }
            }
        }
    }

    @ViewBuilder
    private func restAreasRows(cornerCount: Int) -> some View {
        InspectorNote(text: cornerCount == 1
                          ? "The tool leaves material in 1 corner."
                          : "The tool leaves material in \(cornerCount) corners.",
                      isIndented: false)
        ToggleField(title: "Show rest areas",
                    isOn: showsRestAreas,
                    help: "Outline the corners this tool couldn't reach on the canvas.")
        HStack {
            Spacer(minLength: 0)
            Button {
                onCreateRest()
            } label: {
                Label("Create rest operation", systemImage: "angle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Add a toolpath after this one that cuts these corners with a smaller tool")
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
