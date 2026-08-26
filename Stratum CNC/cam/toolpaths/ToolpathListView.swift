//
//  Toolpath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct Toolpath: Identifiable {
    let id = UUID()

    var name: String
    var type: String
    var toolDiameter: Double
    var depth: Double
    var pathLength: Double
    var estimatedTime: TimeInterval

    var feedRate: Double
    var plungeRate: Double
    var spindleRPM: Int
    var stepDown: Double
    var stepOver: Double
    var safeZ: Double
    var passes: Int
}

struct ToolpathListView: View {
    @State private var toolpaths: [ToolpathData] = []
//    [
//        ToolpathData(
//            name: "Outer Profile",
//            tool: Tool(
//                number: 2,
//                diameter: 6.0,
//                name: "6 mm End Mill"
//            ),
//            startZ: 0,
//            endZ: -3,
//            contour: .outside,
//            ramping: RampingSettings(
//                enabled: true,
//                type: .linear,
//                angle: 3,
//                length: 20
//            ),
//            feedRate: 1200,
//            plungeRate: 400,
//            spindleRPM: 18000,
//            stepDown: 0.1,
//            stepOver: 0.1,
//            safeZ: 5.0
//        ),
//
//        ToolpathData(
//            name: "Inner Cutout",
//            tool: Tool(
//                number: 1,
//                diameter: 3.0,
//                name: "3 mm End Mill"
//            ),
//            startZ: 0,
//            endZ: -5,
//            contour: .inside,
//            ramping: RampingSettings(
//                enabled: true,
//                type: .helix,
//                angle: 2,
//                length: 15
//            ),
//            feedRate: 900,
//            plungeRate: 250,
//            spindleRPM: 20000,
//            stepDown: 0.1,
//            stepOver: 0.1,
//            safeZ: 5.0
//        ),
//
//        ToolpathData(
//            name: "Engraving Outline",
//            tool: Tool(
//                number: 3,
//                diameter: 1.5,
//                name: "1.5 mm Engraving Tool"
//            ),
//            startZ: 0,
//            endZ: -0.8,
//            contour: .outline,
//            ramping: RampingSettings(
//                enabled: false,
//                type: .none,
//                angle: 0,
//                length: 0
//            ),
//            feedRate: 600,
//            plungeRate: 150,
//            spindleRPM: 16000,
//            stepDown: 0.1,
//            stepOver: 0.1,
//            safeZ: 3.0
//        )
//    ]

    @State private var draggedToolpath: ToolpathData?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {

                ForEach($toolpaths) { $toolpath in

                    ToolpathCellView(
                        toolpath: $toolpath
                    )
                    .padding(.bottom, 8)
                    .onDrag {
                        draggedToolpath = toolpath

                        return NSItemProvider(
                            object: toolpath.id.uuidString as NSString
                        )
                    }
                    .onDrop(
                        of: [.text],
                        delegate: ToolpathDropDelegate(
                            target: toolpath,
                            toolpaths: $toolpaths,
                            draggedToolpath: $draggedToolpath
                        )
                    )
                }
            }
            .padding(8)
        }
    }
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
