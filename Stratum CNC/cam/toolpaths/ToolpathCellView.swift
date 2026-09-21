//
//  ContourToolpathRow.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolpathCellView: View {
    @Binding var toolpath: ToolpathData

    /// True while the canvas is in "select shapes" mode for this toolpath.
    var isPicking: Bool = false
    /// Enters shape-picking mode for this toolpath, or leaves it if already active.
    var onTogglePicking: () -> Void = {}

    /// Result of the last Generate for this toolpath, if any.
    var generation: ToolpathGeneration? = nil
    /// True while the generation is running in the background.
    var isGenerating: Bool = false
    /// Builds the toolpaths from the selected shapes.
    var onGenerate: () -> Void = {}

    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Main row

            VStack(spacing: 8) {

                HStack {
                    Text(toolpath.name)
                        .font(.system(size: 15, weight: .semibold))

                    Spacer()

                    shapesButton

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            expanded.toggle()
                        }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {

                    // What the toolpath does
                    OperationPicker(kind: $toolpath.operation.kind)

                    // Tool
                    ToolPicker(tool: $toolpath.tool)

                    // Z range (a counterbore has its own depth instead of an End Z)
                    NumberField(title: "START Z", value: $toolpath.startZ, suffix: "mm")
                    if toolpath.operation.kind.usesEndZ {
                        NumberField(title: "END Z", value: $toolpath.endZ, suffix: "mm")
                    }
                }

                // Side, direction, entry, diameters… depending on the operation
                OperationOptionsView(toolpath: $toolpath)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)

            // MARK: Expanded

            if expanded {
                Divider()

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        NumberField(title: "FEED", value: $toolpath.feedRate, suffix: "mm/min")
                        IntField(title: "SPINDLE", value: $toolpath.spindleRPM, suffix: "RPM")
                    }
                    HStack(spacing: 10) {
                        if toolpath.operation.kind.usesStepdown {
                            NumberField(title: "STEPDOWN", value: $toolpath.stepDown, suffix: "mm")
                        }
                        if toolpath.operation.kind.usesStepover {
                            NumberField(title: "STEPOVER", value: $toolpath.stepOver, suffix: "mm")
                        }
                        NumberField(title: "SAFE Z", value: $toolpath.safeZ, suffix: "mm")
                    }
                }
                .padding(10)
            }

            // MARK: Generate

            Divider()

            generateRow
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
        .overlay {
            // Marks which toolpath the canvas clicks are going to
            if isPicking {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.orange, lineWidth: 2)
                    .allowsHitTesting(false)
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
            .controlSize(.small)
            .disabled(toolpath.targets.isEmpty || isGenerating)
            .help(toolpath.targets.isEmpty
                  ? "Select the shapes to cut first"
                  : "Generate the toolpaths for the selected shapes")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var generationStatus: some View {
        if let generation {
            if let message = generation.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(size: 11))
            } else if !generation.isCurrent(for: toolpath) {
                Label("Outdated — generate again", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11))
            } else {
                Label(successText(for: generation), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
            }
        }
    }

    private func successText(for generation: ToolpathGeneration) -> String {
        let toolpaths = generation.outputCount
        let passes = generation.passCount
        return "\(toolpaths) toolpath\(toolpaths == 1 ? "" : "s") · \(passes) pass\(passes == 1 ? "" : "es")"
    }

    // MARK: Shapes

    /// "Select shapes" -> (canvas picking mode, button becomes "Done") -> back.
    /// Esc also closes the mode while it's active.
    private var shapesButton: some View {
        Button {
            onTogglePicking()
        } label: {
            Label(shapesTitle,
                  systemImage: isPicking ? "checkmark.circle.fill" : "cursorarrow.click")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isPicking ? .orange : nil)
        .keyboardShortcut(isPicking ? .cancelAction : nil)
        .help(isPicking
              ? "Click shapes on the canvas to add or remove them. Click Done (or press Esc) when finished."
              : "Choose which shapes on the canvas this toolpath cuts")
    }

    private var shapesTitle: String {
        let count = toolpath.targets.count
        if isPicking {
            return count == 0 ? "Done" : "Done (\(count) selected)"
        }
        switch count {
        case 0: return "Select shapes"
        case 1: return "1 shape"
        default: return "\(count) shapes"
        }
    }
}

#Preview {
    @Previewable @State var data = ToolpathData(
        id: UUID(),
        name: "Test path",
        tool: Tool(
            id: UUID(),
            name: "3.175*12mm",
            shankDiameter: 3.175,
            toolDiameter: 3.175,
            length: 12,
            type: .endMill,
            group: nil,
            tipAngle: 90,
            parameters: [:]
        ),
        startZ: 0,
        endZ: -2,
        contour: .inside,
        ramping: RampingSettings(
            enabled: true,
            type: .linear,
            angle: 3,
            length: 10
        ),
        feedRate: 300,
        plungeRate: 300,
        spindleRPM: 1200,
        stepDown: 0.1,
        stepOver: 0.1,
        safeZ: 3
    )
    ToolpathCellView(toolpath: $data)
}

//struct ToolpathRow1: View {
//    let toolpath: Toolpath
//    let isExpanded: Bool
//    let onToggle: () -> Void
//
//    var body: some View {
//        VStack(spacing: 0) {
//
//            // MARK: - Always visible
//
//            HStack(spacing: 6) {
//
//                Circle()
//                    .fill(.blue)
//                    .frame(width: 7, height: 7)
//
//                VStack(alignment: .leading, spacing: 1) {
//                    Text(toolpath.name)
//                        .font(.system(size: 12, weight: .semibold))
//
//                    Text(toolpath.type)
//                        .font(.system(size: 9))
//                        .foregroundStyle(.secondary)
//                }
//
//                Spacer(minLength: 4)
//
//                Metric(
//                    value: "Ø\(format(toolpath.toolDiameter))",
//                    label: "TOOL"
//                )
//
//                Metric(
//                    value: "Z\(format(toolpath.depth))",
//                    label: "DEPTH"
//                )
//
//                Metric(
//                    value: formatLength(toolpath.pathLength),
//                    label: "PATH"
//                )
//
//                Metric(
//                    value: formatTime(toolpath.estimatedTime),
//                    label: "TIME"
//                )
//
//                Button(action: onToggle) {
//                    Image(systemName:
//                        isExpanded
//                        ? "chevron.up"
//                        : "chevron.down"
//                    )
//                    .font(.system(size: 9, weight: .bold))
//                    .frame(width: 18, height: 18)
//                }
//                .buttonStyle(.plain)
//            }
//            .padding(.horizontal, 7)
//            .padding(.vertical, 5)
//
//            // MARK: - Expanded information
//
//            if isExpanded {
//                VStack(spacing: 3) {
//
//                    Divider()
//                        .opacity(0.5)
//
//                    HStack(spacing: 10) {
//                        Detail("Feed", "\(format(toolpath.feedRate)) mm/min")
//                        Detail("Plunge", "\(format(toolpath.plungeRate)) mm/min")
//                        Detail("Spindle", "\(toolpath.spindleRPM) RPM")
//                        Detail("Passes", "\(toolpath.passes)")
//                    }
//
//                    HStack(spacing: 10) {
//                        Detail("Stepdown", "\(format(toolpath.stepDown)) mm")
//                        Detail("Stepover", "\(format(toolpath.stepOver)) mm")
//                        Detail("Safe Z", "\(format(toolpath.safeZ)) mm")
//                    }
//                }
//                .padding(.horizontal, 8)
//                .padding(.bottom, 6)
//            }
//        }
//        .background(
//            RoundedRectangle(cornerRadius: 4)
//                .fill(.quaternary.opacity(0.35))
//        )
//    }
//
//    private func format(_ value: Double) -> String {
//        if value == value.rounded() {
//            return String(format: "%.0f", value)
//        }
//
//        return String(format: "%.2f", value)
//    }
//
//    private func formatLength(_ value: Double) -> String {
//        if value >= 1000 {
//            return String(format: "%.1f m", value / 1000)
//        }
//
//        return String(format: "%.0f mm", value)
//    }
//
//    private func formatTime(_ value: TimeInterval) -> String {
//        let seconds = Int(value)
//
//        if seconds >= 3600 {
//            return String(
//                format: "%d:%02d:%02d",
//                seconds / 3600,
//                (seconds % 3600) / 60,
//                seconds % 60
//            )
//        }
//
//        return String(
//            format: "%d:%02d",
//            seconds / 60,
//            seconds % 60
//        )
//    }
//}
//
//struct Metric: View {
//    let value: String
//    let label: String
//
//    var body: some View {
//        VStack(alignment: .trailing, spacing: 0) {
//            Text(value)
//                .font(.system(size: 10, weight: .medium))
//                .monospacedDigit()
//
//            Text(label)
//                .font(.system(size: 7))
//                .foregroundStyle(.secondary)
//        }
//    }
//}
//
//struct Detail: View {
//    let title: String
//    let value: String
//
//    init(_ title: String, _ value: String) {
//        self.title = title
//        self.value = value
//    }
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 0) {
//            Text(title.uppercased())
//                .font(.system(size: 7))
//                .foregroundStyle(.secondary)
//
//            Text(value)
//                .font(.system(size: 9))
//                .monospacedDigit()
//        }
//    }
//}
