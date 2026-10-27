//
//  PanelToolpathDetails.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 14.10.2026.
//


//
//  PanelToolpathDetails.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI
import StratumCAM

struct PanelToolpathDetails: View {
    @Binding var toolpath: ToolpathData

    /// The stock being cut, used to choose the tool's preset when a tool is picked.
    var stockMaterial: StockMaterialType

    /// Every other toolpath's current name, so the auto-generated name for this
    /// one (see `operationKindBinding`) picks a number that isn't already taken.
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
    /// The preview slider moved to this step (0 = nothing cut yet, up to the generation's
    /// `scrub.stepCount` = the whole toolpath). Fires on every tick of a drag.
    var onScrub: (Int) -> Void = { _ in }
    var onDone: () -> Void = {}
    /// Removes this toolpath (and closes the panel).
    var onDelete: () -> Void = {}
    /// Adds another toolpath after this one and opens it.
    var onAddNext: () -> Void = {}

    /// What the last tool pick did to the cutting values, shown under the tool.
    @State private var presetNote: String?

    /// Where the preview slider is; nil = at the end (the whole toolpath), which is where a
    /// new result starts. Kept here rather than in the model so a drag only redraws this panel.
    @State private var scrubStep: Int?

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
                InspectorSection(title: "Tool") {
                    rowTool
                }
                InspectorSection(title: "Depth") {
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
                presetNote = nil
                scrubStep = nil
            }
            // A new Generate starts its preview from the end again, like the canvas does
            .onChange(of: generation?.id) { _, _ in scrubStep = nil }
        }
    }

    // MARK: Generate

    @ViewBuilder
    private var rowHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: toolpath.operation.kind.symbol)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            // Typing here is what makes a name "custom" -- from then on it stops
            // following the operation (see `operationKindBinding`).
            TextField("", text: Binding(
                get: { toolpath.name },
                set: {
                    toolpath.name = $0
                    toolpath.isNameCustom = true
                }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .background(.background)
        }
    }

    @ViewBuilder
    private var rowOperation: some View {
        OperationPicker(kind: operationKindBinding)
    }

    /// Changing the operation also renames the toolpath to match -- "Contour 1",
    /// "Pocket 1", ... -- but only while the name is still the auto-generated one;
    /// once the user has typed their own title it stops following the operation.
    private var operationKindBinding: Binding<OperationKind> {
        Binding(
            get: { toolpath.operation.kind },
            set: { newKind in
                toolpath.operation.kind = newKind
                // Untouched fields take the new operation's defaults; edited ones stay.
                toolpath.applyDefaults(for: newKind)
                if !toolpath.isNameCustom {
                    toolpath.name = newKind.nextName(among: siblingNames)
                }
            }
        )
    }

    /// A binding that also records the field as edited when the user changes its value,
    /// so changing the operation later leaves it alone.
    private func editedBinding(_ value: Binding<Double>, _ field: ToolpathField) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                guard newValue != value.wrappedValue else {
                    return
                }
                value.wrappedValue = newValue
                toolpath.markEdited(field)
            }
        )
    }

    /// Which of the general fields (End Z, Stepdown, Stepover) the operation reads, as the
    /// library defines it for the operation's current values.
    private var requirements: SC.OperationRequirements {
        toolpath.machiningOperation.requirements
    }

    @ViewBuilder
    private var rowOperationOptions: some View {
        // Side, direction, entry, diameters… whatever SC.MachiningOperation.formFields
        // defines for the chosen operation
        OperationOptionsView(toolpath: $toolpath)
        // Stepover is part of OperationOptionsView, so it sits next to the clearing pattern.
    }

    @ViewBuilder
    private var rowTool: some View {
        ToolPicker(tool: $toolpath.tool, onToolPicked: applyPreset(of:))
        if let presetNote {
            InspectorNote(text: presetNote)
        }
        InspectorIntField(title: "Spindle", value: $toolpath.spindleRPM, suffix: "rpm")
        InspectorNumberField(title: "Feed rate", value: $toolpath.feedRate, suffix: "mm/min")
    }

    /// Fills spindle speed, feeds, stepdown and ramp angle from the picked tool's
    /// preset for the current stock. Only runs on an explicit pick, so opening a
    /// toolpath never overwrites its values.
    private func applyPreset(of tool: Tool) {
        if let preset = tool.preset(for: stockMaterial) {
            toolpath.apply(preset)
            presetNote = "Applied the \"\(preset.name)\" preset"
        } else if tool.presets.isEmpty {
            presetNote = "This tool has no presets; values unchanged"
        } else {
            presetNote = "No preset for \(stockMaterial.displayName); values unchanged"
        }
    }

    @ViewBuilder
    private var rowDepth: some View {
        // Z range (a counterbore has its own depth instead of an End Z)
        InspectorNumberField(title: "Start Z", value: $toolpath.startZ, suffix: "mm")
        if requirements.usesEndZ {
            InspectorNumberField(title: "End Z", value: editedBinding($toolpath.endZ, .endZ), suffix: "mm")
        }
        if requirements.usesStepdown {
            InspectorNumberField(title: "Stepdown", value: editedBinding($toolpath.stepDown, .stepDown), suffix: "mm")
        }
        InspectorNumberField(title: "Clearance Z", value: $toolpath.safeZ, suffix: "mm")
    }

    /// How many shapes the toolpath cuts. Shapes are chosen by clicking them on
    /// the canvas while the cell is open, so there's nothing to press here.
    private var rowShapes: some View {
        InspectorRow(label: "Selected") {
            shapesLabel
        }
    }

    /// Generation status on the left, the Preview button on the right. Preview builds the
    /// toolpath from the selected shapes and shows it on the canvas.
    @ViewBuilder
    private var rowPreview: some View {
        // Only offered once there are shapes to cut
        if toolpath.targets.isEmpty {
            InspectorNote(text: "Select shapes to preview the toolpath.")
        } else {
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
                .help(toolpath.leadInConflictsWithEntry
                      ? "A lead-in can't be combined with a ramp or helix entry. Turn the entry off or remove the lead-in."
                      : "Build the toolpath for the selected shapes and preview it on the canvas")
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
                Label(successText(for: generation), systemImage: "checkmark.circle.fill")
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
                Slider(value: Binding(
                    get: { Double(scrubStep ?? total) },
                    set: { newValue in
                        let step = Int(newValue.rounded())
                        guard step != (scrubStep ?? total) else {
                            return
                        }
                        scrubStep = step
                        onScrub(step)
                    }
                ), in: 0...Double(total))
                .controlSize(.small)

                Text("\(scrubStep ?? total) / \(total)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .help("Scrub through the generated toolpath")
        }
    }

    private func successText(for generation: ToolpathGeneration) -> String {
        let toolpaths = generation.outputCount
        let passes = generation.passCount
        return "\(toolpaths) toolpath\(toolpaths == 1 ? "" : "s") · \(passes) pass\(passes == 1 ? "" : "es")"
    }

    // MARK: Shapes

    /// How many shapes the toolpath cuts. Shapes are chosen by clicking them on
    /// the canvas while the cell is open, so there's nothing to press here.
    private var shapesLabel: some View {
        Label(shapesTitle, systemImage: "cursorarrow.click")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(toolpath.targets.isEmpty ? Color.orange : Color.secondary)
            .help("Click shapes on the canvas to add or remove them")
    }

    private var shapesTitle: String {
        switch toolpath.targets.count {
            case 0: return "Click shapes to select"
            case 1: return "1 shape selected"
            default: return "\(toolpath.targets.count) shapes selected"
        }
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
