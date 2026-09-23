//
//  PanelToolpathDetails.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct PanelToolpathDetails: View {
    @Binding var toolpath: ToolpathData

    /// True while the canvas is picking shapes for this toolpath. That's the case
    /// whenever the cell is open: clicking a shape on the canvas adds/removes it.
    var isPicking: Bool = false

    /// Result of the last Generate for this toolpath, if any.
    var generation: ToolpathGeneration? = nil
    /// True while the generation is running in the background.
    var isGenerating: Bool = false
    /// Builds the toolpaths from the selected shapes.
    var onGenerate: () -> Void = {}
    var onDone: () -> Void = {}

    /// Expanded lays every picker's options directly in the view instead of behind
    /// a dropdown or a popover — quicker to scan and to change, at the cost of
    /// height. Operation stays a popover either way: its grid of every operation
    /// is too large to sit inline without pushing everything else off screen.
    @State private var isExpanded = true

    var body: some View {
        GroupBox("TOOLPATH") {
            VStack(alignment: .leading, spacing: 8) {
                rowHeader
                Divider()
                rowOperation
                Divider()
                rowOperationOptions
                Divider()
                rowDirection
                Divider()
                rowRamping
                Divider()
                rowZ
                Divider()
                rowFooter
            }
            .padding(16)
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
            TextField("", text: $toolpath.name)
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
        HStack(alignment: .top, spacing: 8) {
            OperationPicker(kind: $toolpath.operation.kind)
            ToolPicker(tool: $toolpath.tool)
            NumberField(title: "FEED", value: $toolpath.feedRate, suffix: "mm/min")
        }
    }

    @ViewBuilder
    private var rowOperationOptions: some View {
        VStack(alignment: .leading) {
            // Side, direction, entry, diameters… depending on the operation
            OperationOptionsView(toolpath: $toolpath, expanded: isExpanded)
                .frame(maxWidth: .infinity, alignment: .leading)
            if toolpath.operation.kind.usesStepover {
                NumberField(title: "STEPOVER", value: $toolpath.stepOver, suffix: "mm")
            }
        }
    }

    @ViewBuilder
    private var rowDirection: some View {
    }

    @ViewBuilder
    private var rowRamping: some View {
        IntField(title: "SPINDLE", value: $toolpath.spindleRPM, suffix: "RPM")
    }

    @ViewBuilder
    private var rowZ: some View {
        HStack(spacing: 8) {
            // Z range (a counterbore has its own depth instead of an End Z)
            NumberField(title: "START Z", value: $toolpath.startZ, suffix: "mm")
            if toolpath.operation.kind.usesEndZ {
                NumberField(title: "END Z", value: $toolpath.endZ, suffix: "mm")
            }
            if toolpath.operation.kind.usesStepdown {
                NumberField(title: "STEPDOWN", value: $toolpath.stepDown, suffix: "mm")
            }
            NumberField(title: "SAFE Z", value: $toolpath.safeZ, suffix: "mm")
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
                HStack(spacing: 8) {
                    generationStatus
                    Spacer(minLength: 8)
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
                    .lineLimit(1)
            } else if !generation.isCurrent(for: toolpath) {
                Label("Outdated...", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11))
            } else {
                Label(successText(for: generation), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
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
