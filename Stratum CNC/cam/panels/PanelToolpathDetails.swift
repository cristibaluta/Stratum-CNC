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

    /// Expanded lays every picker's options directly in the view instead of behind
    /// a dropdown or a popover — quicker to scan and to change, at the cost of
    /// height. Operation stays a popover either way: its grid of every operation
    /// is too large to sit inline without pushing everything else off screen.
    @State private var isExpanded = true

    /// What the last tool pick did to the cutting values, shown under the tool.
    @State private var presetNote: String?

    /// Where the preview slider is; nil = at the end (the whole toolpath), which is where a
    /// new result starts. Kept here rather than in the model so a drag only redraws this panel.
    @State private var scrubStep: Int?

    var body: some View {
        GroupBox("TOOLPATH PARAMS") {
            VStack(alignment: .leading, spacing: 16) {
                rowHeader
                Divider().background(.orange.opacity(0.5))
                rowOperation
                Divider()
                rowOperationOptions
                Divider().background(.orange.opacity(0.5))
                rowTool
                Divider()
                rowPasses
                rowSafeZ
                Divider().background(.orange.opacity(0.5))
                rowFooter
                generationStatus
                rowScrub
            }
            .padding(16)
            .onChange(of: toolpath.id) { _, _ in
                presetNote = nil
                scrubStep = nil
            }
            // A new Generate starts its preview from the end again, like the canvas does
            .onChange(of: generation?.id) { _, _ in scrubStep = nil }
            .overlay {
                // Marks which toolpath the canvas clicks are going to
                if isPicking {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.orange, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Generate

    @ViewBuilder
    private var rowHeader: some View {
        HStack {
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
            Spacer()
            expandToggle
            doneButton
        }
    }

    @ViewBuilder
    private var rowOperation: some View {
        HStack(alignment: .bottom, spacing: 16) {
            OperationPicker(kind: operationKindBinding)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private var hint: String {
        if toolpath.operation.kind == .slotting {
            switch toolpath.operation.slotSource {
            case .outline:
                return "Select the slot's outline: a closed, straight-sided rectangle exactly as wide as the tool."
            case .centerline:
                return "Select the line the tool centre follows; the slot is as wide as the tool."
            }
        }
        return toolpath.operation.kind.selectionHint ?? ""
    }

    @ViewBuilder
    private var rowOperationOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Side, direction, entry, diameters… whatever SC.MachiningOperation.formFields
            // defines for the chosen operation
            OperationOptionsView(toolpath: $toolpath, expanded: isExpanded)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Adaptive clearing is driven by its optimal load, not by the stepover.
            if toolpath.operation.kind.usesStepover,
               !(toolpath.operation.kind == .pocket && toolpath.operation.pocketPattern == .adaptive) {
                NumberField(title: "STEPOVER", value: editedBinding($toolpath.stepOver, .stepOver), suffix: "%")
            }
        }
    }

    @ViewBuilder
    private var rowTool: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPicker(tool: $toolpath.tool, onToolPicked: applyPreset(of:))
            if let presetNote {
                Text(presetNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 8) {
                IntField(title: "SPINDLE SPEED", value: $toolpath.spindleRPM, suffix: "RPM")
                NumberField(title: "FEED RATE", value: $toolpath.feedRate, suffix: "mm/min")
            }
        }
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
    private var rowPasses: some View {
        HStack(spacing: 8) {
            // Z range (a counterbore has its own depth instead of an End Z)
            NumberField(title: "START Z", value: $toolpath.startZ, suffix: "mm")
            if toolpath.operation.kind.usesEndZ {
                NumberField(title: "END Z", value: editedBinding($toolpath.endZ, .endZ), suffix: "mm")
            }
            if toolpath.operation.kind.usesStepdown {
                NumberField(title: "STEPDOWN", value: editedBinding($toolpath.stepDown, .stepDown), suffix: "mm")
            }
        }
    }

    @ViewBuilder
    private var rowSafeZ: some View {
        HStack(spacing: 8) {
            NumberField(title: "CLEARANCE Z", value: $toolpath.safeZ, suffix: "mm")
        }
    }

    @ViewBuilder
    private var rowFooter: some View {
        HStack {
            shapesLabel
            Spacer()
            // We show generate only if we have selected shapes
            if !toolpath.targets.isEmpty {
                Divider()
                    .frame(height: 20)

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
                        Label("Generate", systemImage: "wand.and.stars")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
                .help("Generate the toolpaths for the selected shapes")
            }
        }
        .frame(height: 36)
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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("PREVIEW", systemImage: "scope")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(scrubStep ?? total) / \(total)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
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

    /// Toggles between the compact layout (dropdowns/popovers/menus) and the
    /// expanded one (every option laid out directly in the view).
    private var expandToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(isExpanded ? "Collapse to dropdowns" : "Expand — show all options directly")
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
