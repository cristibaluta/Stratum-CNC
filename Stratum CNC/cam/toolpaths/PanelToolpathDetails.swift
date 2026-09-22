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

    var body: some View {
        GroupBox("TOOLPATH") {
            VStack(spacing: 0) {
                VStack(spacing: 8) {

                    HStack {
                        Text(toolpath.name)
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        doneButton
                    }

                    Divider()

                    HStack(spacing: 8) {
                        // What the toolpath does
                        OperationPicker(kind: $toolpath.operation.kind)
                        // Tool
                        ToolPicker(tool: $toolpath.tool)
                        // Feed
                        NumberField(title: "FEED", value: $toolpath.feedRate, suffix: "mm/min")
                    }

                    // Side, direction, entry, diameters… depending on the operation
                    OperationOptionsView(toolpath: $toolpath)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // MARK: Expanded

                Divider()

                VStack(spacing: 10) {
                    HStack {
                        IntField(title: "SPINDLE", value: $toolpath.spindleRPM, suffix: "RPM")
                        if toolpath.operation.kind.usesStepover {
                            NumberField(title: "STEPOVER", value: $toolpath.stepOver, suffix: "mm")
                        }
                    }
                    HStack(spacing: 10) {
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
                .padding(10)

                // MARK: Generate

                Divider()

                HStack {
                    shapesLabel
                    Divider()
                        .frame(height: 20)
                    Spacer()
                    // We show generate only if we have selected shapes
                    if !toolpath.targets.isEmpty {
                        generateRow
                    }
                }
                .frame(height: 36)
            }
            .padding(10)
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

    private var generateRow: some View {
        HStack(spacing: 10) {
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
