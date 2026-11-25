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

    /// A rest toolpath only: the pocket it is linked to, nil when that one is gone.
    var restSource: ToolpathData? = nil
    var onDone: () -> Void = {}
    var onDelete: () -> Void = {}
    /// Adds another toolpath after this one and opens it.
    /// The outlines of the selected shapes in world space, one per shape, for drawings in the
    /// panel (where the holding tabs sit). Called only when a drawing is shown.
    var targetShapes: () -> [CGPath] = { [] }
    /// The selected shapes described one by one (kind, size, distance to Z0), for the expandable
    /// "Selected" row. Called when the row is open and the selection changes.
    var shapeDetails: () -> [ShapeDetail] = { [] }

    @StateObject private var model = ToolpathDetailsModel()

    /// The "Selected" row is open and lists every selected shape.
    @State private var isShapesExpanded = false
    @State private var shapeList: [ShapeDetail] = []

    /// The title section's compact form is showing. Remembered like the other sections'.
    @AppStorage("inspector.sectionCollapsed.Title") private var isTitleCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                                        isRest: toolpath.operation.isRest,
                                        isCompact: true)
                        // A rest operation is created from a pocket and stays one.
                        .disabled(toolpath.operation.isRest)
                        if OperationOptionsView.hasOperationFields(for: toolpath) {
                            OperationOptionsView(toolpath: $toolpath, part: .operationCompact)
                        }
                    }
                } else {
                    rowOperation
                    InspectorNote(text: toolpath.operation.summary)
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
                OperationOptionsView(toolpath: $toolpath, targetShapes: targetShapes, stockMaterial: stockMaterial, part: .xyCompact)
            }) {
                rowXYMovement
            }
            // Start Z, End Z, the depth per pass, the Safe and Retract heights, and the holding tabs.
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
            rowBottomBar
        }
        .padding(12)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
        .onChange(of: toolpath.id) { _, _ in
            model.reset()
        }
        // The cutting values come from the tool's preset for the stock material
        .onChange(of: stockMaterial) { _, newMaterial in
            model.applyPreset(of: toolpath.tool, to: $toolpath, stockMaterial: newMaterial)
        }
    }

    // MARK: Generate

    @ViewBuilder
    private var rowHeader: some View {
        HStack(spacing: 8) {
            OperationIcon(kind: toolpath.operation.kind, isRest: toolpath.operation.isRest, size: 16)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            // The name is reset to the operation's auto name whenever the operation is
            // changed (see `operationKindBinding`), and is free text otherwise.
            TextField("", text: model.nameBinding($toolpath))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
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
        OperationPicker(kind: model.operationKindBinding($toolpath, siblingNames: siblingNames),
                        isRest: toolpath.operation.isRest)
            // A rest operation is created from a pocket and stays one.
            .disabled(toolpath.operation.isRest)
    }

    /// Which of the general fields (End Z, Stepdown, Stepover) the operation reads.
    private var requirements: SC.OperationRequirements {
        model.requirements(for: toolpath)
    }

    @ViewBuilder
    private var rowXYMovement: some View {
        OperationOptionsView(toolpath: $toolpath, targetShapes: targetShapes, stockMaterial: stockMaterial, part: .xyMovement)
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
        // Worked out from the values every time; nothing about it is saved
        if let mismatch = toolpath.presetMismatch(for: stockMaterial) {
            InspectorNote(text: mismatch.message)
            HStack(alignment: .center, spacing: Inspector.columnSpacing) {
                Color.clear
                    .frame(width: Inspector.labelWidth, height: 0)
                Button("Use recommended values") {
                    model.applyPreset(of: toolpath.tool, to: $toolpath, stockMaterial: stockMaterial)
                }
                .controlSize(.small)
                Spacer(minLength: 0)
            }
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
            if let mismatch = toolpath.presetMismatch(for: stockMaterial) {
                Button {
                    model.applyPreset(of: toolpath.tool, to: $toolpath, stockMaterial: stockMaterial)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 12))
                        .frame(width: 20, height: Inspector.fieldHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(mismatch.message)\nClick to use the recommended values.")
            }
        }
    }

    /// The ramp or helix, the feed going down and, for a contour, the lead-in and lead-out.
    @ViewBuilder
    private var rowEntry: some View {
        // How the tool gets down into the material: ramp, helix or plunge.
        if OperationOptionsView.hasEntry(for: toolpath) {
            OperationOptionsView(toolpath: $toolpath, part: .entry)
        }
        InspectorNumberField(title: "Start offset", value: $toolpath.startOffset, suffix: "mm")
            .help("How far above Start Z the entry starts. The tool rapids down to here, then enters: a ramp or helix starts its angled descent from this height, a plunge feeds straight down from it.")
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
        if toolpath.operation.kind == .chamfer {
            chamferZRows
        } else {
            InspectorNumberField(title: "Start Z", value: $toolpath.startZ, suffix: "mm")
                .help("The height where cutting starts. 0 is the top of the stock; passes above it are skipped.")
        }
        if toolpath.operation.kind == .chamfer {
            // Shown above (calculated): a chamfer has no End Z of its own.
        } else if toolpath.operation.kind == .counterbore {
            InspectorNumberField(title: "End Z", value: model.counterboreEndDepth($toolpath), suffix: "mm", prefix: "−")
                .help("How deep the counterbore goes below the top of the stock.")
        } else if requirements.usesEndZ {
            InspectorNumberField(title: "End Z", value: model.endDepth($toolpath), suffix: "mm", prefix: "−") {
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
            InspectorNumberField(title: "Stepdown", value: $toolpath.stepDown, suffix: "mm",
                                 offersDecimalsOnly: true)
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
        InspectorNumberField(title: "Safe Z", value: $toolpath.safeZ, suffix: "mm")
            .help("The height the tool starts and ends at, and travels at between distant cuts.")
        InspectorNumberField(title: "Retract Z", value: $toolpath.retractZ, suffix: "mm")
            .help("The height the tool lifts to between passes. Not higher than Safe Z.")
        // Holding tabs (contour): material left standing at the bottom of the cut. Last in the
        // section, after the heights.
        if OperationOptionsView.hasTabs(for: toolpath) {
            OperationOptionsView(toolpath: $toolpath, targetShapes: targetShapes, part: .tabs)
        }
    }

    /// A chamfer's Start Z and End Z, calculated and not editable. Start Z is the top of the bevel
    /// (the top edge). End Z is where the tool TIP ends, which is the bevel's bottom minus the tip
    /// offset, so with an offset it is lower than the finished edge.
    @ViewBuilder
    private var chamferZRows: some View {
        if let range = toolpath.chamferZRange {
            InspectorNumberField(title: "Start Z", value: .constant(range.start), suffix: "mm")
                .help(Self.chamferStartZHelp)
                .disabled(true)
                .opacity(0.5)
            InspectorNumberField(title: "End Z", value: .constant(-range.end), suffix: "mm", prefix: "\u{2212}")
                .help(Self.chamferEndZHelp)
                .disabled(true)
                .opacity(0.5)
        }
    }

    private static let chamferStartZHelp = "Calculated, not editable: the top of the bevel, where the cut starts. It follows the Z of the selected edge, read from the model (the edge itself for a top edge, the edge plus the bevel's depth for a bottom edge)."
    private static let chamferEndZHelp = "Calculated, not editable: where the tool tip ends. For a bottom edge the bevel's bottom is the edge's Z from the model, for a top edge it is that Z minus the bevel's depth; the tip offset goes lower still, so with an offset the tip ends below the finished edge."

    /// The Z axis section's collapsed form: where the cut starts and ends and how deep each
    /// pass goes, then the Safe Z. Retract Z, the holding tabs and the operation's own
    /// depth settings are in the full section only.
    @ViewBuilder
    private var rowDepthCompact: some View {
        let isSlot = toolpath.operation.kind == .slotting
        let stepdown = isSlot ? toolpath.operation.slotDepthPerPass : toolpath.stepDown
        let passes = model.passesNote(for: toolpath, stepdown: stepdown)

        HStack(spacing: 6) {
            if toolpath.operation.kind == .chamfer {
                if let range = toolpath.chamferZRange {
                    InspectorCompactNumberField(tag: "Start",
                                                value: .constant(range.start),
                                                help: "Start Z (mm). \(Self.chamferStartZHelp)")
                        .disabled(true)
                        .opacity(0.5)
                    InspectorCompactNumberField(tag: "End",
                                                value: .constant(-range.end),
                                                prefix: "\u{2212}",
                                                help: "End Z (mm). \(Self.chamferEndZHelp)")
                        .disabled(true)
                        .opacity(0.5)
                }
            } else {
                InspectorCompactNumberField(tag: "Start",
                                            value: $toolpath.startZ,
                                            help: "Start Z (mm): the height where cutting starts. 0 is the top of the stock.")
            }
            if toolpath.operation.kind == .chamfer {
                // End Z is shown above (calculated).
            } else if toolpath.operation.kind == .counterbore {
                InspectorCompactNumberField(tag: "End",
                                            value: model.counterboreEndDepth($toolpath),
                                            prefix: "−",
                                            help: "End Z (mm): how deep the counterbore goes below the top of the stock.")
            } else if requirements.usesEndZ {
                InspectorCompactNumberField(tag: "End",
                                            value: model.endDepth($toolpath),
                                            prefix: "−",
                                            help: "End Z (mm): \(model.endZHelp)")
            }
            if isSlot {
                InspectorCompactNumberField(tag: "Step",
                                            value: model.slotDepthPerPass($toolpath),
                                            help: "Depth per pass (mm). \(passes?.text ?? "")")
            } else if requirements.usesStepdown {
                InspectorCompactNumberField(tag: "Step",
                                            value: $toolpath.stepDown,
                                            decimalKey: "Stepdown",
                                            help: "Stepdown (mm): how deep the tool cuts in each pass. \(passes?.text ?? "")")
            }
            if toolpath.operation.kind == .drilling, toolpath.operation.drillUsesPecking {
                InspectorCompactNumberField(tag: "Peck",
                                            value: model.drillPeckDepth($toolpath),
                                            help: "Peck depth (mm): how deep the drill goes before retracting.")
            }
            InspectorCompactNumberField(tag: "Safe",
                                        value: $toolpath.safeZ,
                                        help: "Safe Z (mm): the height the tool starts and ends at, and travels at between distant cuts.")
            if let passes, passes.isWarning {
                InspectorWarningButton(message: passes.text)
            }
        }
    }

    /// The Entry section's collapsed form: the strategy, its angle and the feed going down.
    /// The Start offset, the lead-in and the lead-out are in the full section only.
    @ViewBuilder
    private var rowEntryCompact: some View {
        HStack(spacing: 6) {
            if OperationOptionsView.hasEntry(for: toolpath) {
                OperationOptionsView(toolpath: $toolpath, part: .entryCompact)
            }
            InspectorCompactNumberField(tag: "Feed",
                                        value: $toolpath.plungeRate,
                                        help: "Entry feed (mm/min). \(model.plungeFeedHelp(for: toolpath))")
        }
    }

    /// A problem with the passes Start Z, End Z and the stepdown come to, under the field that sets
    /// it. Only the warning: how many passes there are is in the preview panel.
    @ViewBuilder
    private func passesNote(stepdown: Double) -> some View {
        if let note = model.passesNote(for: toolpath, stepdown: stepdown), note.isWarning {
            InspectorNote(text: note.text, isWarning: true)
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
        if toolpath.operation.isRest {
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
            if toolpath.hasSelectedTargets, !toolpath.cutsWholeStock {
                Button {
                    isShapesExpanded.toggle()
                    if isShapesExpanded {
                        shapeList = shapeDetails()
                    }
                } label: {
                    HStack(spacing: 6) {
                        shapesLabel
                        Image(systemName: isShapesExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Show the selected shapes")
            } else {
                shapesLabel
            }
        }
        if isShapesExpanded, toolpath.hasSelectedTargets, !toolpath.cutsWholeStock {
            shapeListRows
                .onChange(of: toolpath.targets) { _, _ in shapeList = shapeDetails() }
                .onChange(of: toolpath.stepTargets) { _, _ in shapeList = shapeDetails() }
        }
    }

    /// Every selected shape on its own line: number, kind, size and the distance to Z0.
    private var shapeListRows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(shapeList.enumerated()), id: \.element.id) { index, shape in
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 14, alignment: .trailing)
                        Text(shape.kind)
                        Spacer(minLength: 8)
                        Text(shape.size)
                        Text(shape.z)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .help("\(shape.kind): \(shape.size), \(shape.z)")
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 160)
    }

    /// The bottom bar: delete on the left, close on the right. (Next toolpath and Preview in
    /// Controller sit under the panel, see `CAMView`.)
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

                doneButton
            }
            .padding(.top, 10)
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
