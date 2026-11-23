//
//  PanelToolpathPreview.swift
//  Stratum CNC
//
//  The Generate button, its status and the scrub slider for the open toolpath. Kept out of
//  `PanelToolpathDetails` so it sits in its own panel that does not scroll with the settings:
//  you change a setting and see its effect without scrolling back to it.
//

import SwiftUI
import StratumCAM

struct PanelToolpathPreview: View {
    let toolpath: ToolpathData

    /// Result of the last Generate for this toolpath, if any.
    var generation: ToolpathGeneration? = nil
    /// True while the generation is running in the background.
    var isGenerating: Bool = false
    /// Draw the corners a pocket's tool couldn't reach on the canvas.
    var showsRestAreas: Binding<Bool> = .constant(true)
    /// Adds a rest toolpath after this pocket and opens it.
    var onCreateRest: () -> Void = {}
    /// Rebuilds the toolpath from the selected shapes. Opening the panel already does it (see
    /// `CAMModel.generateIfNeeded`), so this is for refreshing the result after an edit.
    var onGenerate: () -> Void = {}
    var onScrub: (Int) -> Void = { _ in }

    /// Holds the scrub position and the texts under the button.
    @StateObject private var model = ToolpathDetailsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSection(title: "Preview", collapsible: true) {
                rowPreview
                rowScrub
            }
        }
        .padding(12)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
        .onChange(of: toolpath.id) { _, _ in
            model.reset()
        }
        // A new Generate starts its preview from the end again, like the canvas does
        .onChange(of: generation?.id) { _, _ in model.resetScrub() }
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
                        Text("Generate")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isGenerating || !toolpath.hasGeometry || toolpath.toolCompatibilityWarning != nil)
                .help(model.previewButtonHelp(for: toolpath))
            }
            if let timeText = model.timeText(for: generation, toolpath: toolpath) {
                Label(timeText, systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Rough estimate from the length of the moves and their feed rates. Acceleration and tool changes aren't included, so the real time is a little longer.")
            }
            // Warnings don't stop the toolpath, and only matter while the result is current
            if let generation, generation.isCurrent(for: toolpath) {
                ForEach(generation.warningMessages, id: \.self) { message in
                    InspectorNote(text: message, isWarning: true, isIndented: false)
                }
                // The corners this pocket's tool couldn't reach: offer to clean them with a smaller tool
                if toolpath.operation.kind == .pocket, !toolpath.operation.isRest, generation.errorMessage == nil, !generation.restCorners.isEmpty {
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
}
