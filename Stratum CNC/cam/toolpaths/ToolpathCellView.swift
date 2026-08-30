//
//  ContourToolpathRow.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolpathCellView: View {
    @Binding var toolpath: ToolpathData

    @State private var expanded = true
    @State private var showRampEditor = false

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Main row

            VStack(spacing: 8) {

                HStack {
                    Text(toolpath.name)
                        .font(.system(size: 15, weight: .semibold))

                    Spacer()

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

                    // Tool
                    ToolPicker(tool: $toolpath.tool)

                    // Z range
                    ZField(title: "START Z", value: $toolpath.startZ)
                    ZField(title: "END Z", value: $toolpath.endZ)

                    // Contour
                    ContourPicker(selection: $toolpath.contour)

                    // Ramping
                    RampingButton(ramping: toolpath.ramping) {
                        showRampEditor = true
                    }
                    .popover(isPresented: $showRampEditor) {
                        RampingEditor(ramping: $toolpath.ramping, stepdown: toolpath.stepDown)
                            .frame(width: 600)
                    }
                }
            }
            .padding(10)

            // MARK: Expanded

            if expanded {
                Divider()

                VStack(spacing: 10) {

                    HStack(spacing: 10) {

                        NumberField(
                            title: "FEED",
                            value: $toolpath.feedRate,
                            suffix: "mm/min"
                        )

                        NumberField(
                            title: "PLUNGE",
                            value: $toolpath.plungeRate,
                            suffix: "mm/min"
                        )

                        IntField(
                            title: "SPINDLE",
                            value: $toolpath.spindleRPM,
                            suffix: "RPM"
                        )
                    }

                    HStack(spacing: 10) {

                        NumberField(
                            title: "STEPDOWN",
                            value: $toolpath.stepDown,
                            suffix: "mm"
                        )

                        NumberField(
                            title: "STEPOVER",
                            value: $toolpath.stepOver,
                            suffix: "mm"
                        )

                        NumberField(
                            title: "SAFE Z",
                            value: $toolpath.safeZ,
                            suffix: "mm"
                        )
                    }
                }
                .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
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
