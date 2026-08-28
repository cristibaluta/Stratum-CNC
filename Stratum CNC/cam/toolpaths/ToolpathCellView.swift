//
//  ContourToolpathRow.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolpathCellView: View {
    @Binding var toolpath: ToolpathData

    @State private var expanded = false
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
