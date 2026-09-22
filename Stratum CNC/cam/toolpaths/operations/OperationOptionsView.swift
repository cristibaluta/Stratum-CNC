//
//  OperationOptionsView.swift
//  Stratum CNC
//
//  The row of controls that changes with the chosen operation: a contour has a side, a
//  drill has an optional peck depth, a counterbore has a diameter and a depth…
//

import SwiftUI

struct OperationOptionsView: View {
    @Binding var toolpath: ToolpathData

    @State private var showRampEditor = false

    private var kind: OperationKind { toolpath.operation.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            options

            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hint: String? {
        if kind == .slotting {
            switch toolpath.operation.slotSource {
            case .outline:
                return "Select the slot's outline: a closed, straight-sided rectangle exactly as wide as the tool."
            case .centerline:
                return "Select the line the tool centre follows; the slot is as wide as the tool."
            }
        }
        return kind.selectionHint
    }

    // MARK: Per-operation controls

    @ViewBuilder
    private var options: some View {
        switch kind {

        case .contour:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ContourPicker(selection: $toolpath.contour)
                    directionPicker
                }
                rampingRow
            }

        case .pocket:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    EnumMenuPicker(title: "PATTERN", selection: $toolpath.operation.pocketPattern)
                    directionPicker
                }
                switch toolpath.operation.pocketPattern {
                case .spiral:
                    HStack(spacing: 8) {
                        EnumMenuPicker(title: "SPIRAL", selection: $toolpath.operation.pocketSpiral)
                    }
                case .trochoidal:
                    HStack(spacing: 8) {
                        NumberField(title: "LOOP PITCH", value: $toolpath.operation.pocketTrochoidalPitch, suffix: "% radius")
                    }
                case .offset, .raster:
                    EmptyView()
                }
                rampingRow
            }

        case .facing:
            HStack(spacing: 8) {
                directionPicker
                NumberField(title: "EXTENSION", value: $toolpath.operation.facingExtension, suffix: "mm")
            }

        case .slotting:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    EnumMenuPicker(title: "SELECTION IS", selection: $toolpath.operation.slotSource)
                    NumberField(title: "DEPTH / PASS", value: $toolpath.operation.slotDepthPerPass, suffix: "mm")
                }
                rampingRow
            }

        case .engrave:
            EmptyView()

        case .drilling:
            HStack(spacing: 8) {
                ToggleField(title: "PECKING", isOn: $toolpath.operation.drillUsesPecking)
                if toolpath.operation.drillUsesPecking {
                    NumberField(title: "PECK DEPTH", value: $toolpath.operation.drillPeckDepth, suffix: "mm")
                }
            }

        case .counterbore:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    NumberField(title: "DIAMETER", value: $toolpath.operation.counterboreDiameter, suffix: "mm")
                    NumberField(title: "DEPTH", value: $toolpath.operation.counterboreDepth, suffix: "mm")
                }
                HStack(spacing: 8) {
                    directionPicker
                }
                rampingRow
            }

        case .boring:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    NumberField(title: "FINISHED Ø", value: $toolpath.operation.boreTargetDiameter, suffix: "mm")
                    ToggleField(title: "SHIFT RETRACT", isOn: $toolpath.operation.boreShiftRetract)
                }
                HStack(spacing: 8) {
                    ToggleField(title: "DWELL", isOn: $toolpath.operation.boreUsesDwell)
                    if toolpath.operation.boreUsesDwell {
                        NumberField(title: "DWELL TIME", value: $toolpath.operation.boreDwellTime, suffix: "s")
                    }
                }
            }

        case .threadMilling:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    NumberField(title: "PITCH", value: $toolpath.operation.threadPitch, suffix: "mm")
                    NumberField(title: "THREAD Ø", value: $toolpath.operation.threadTargetDiameter, suffix: "mm")
                    IntField(title: "RADIAL PASSES", value: $toolpath.operation.threadRadialPasses, suffix: "")
                }
                HStack(spacing: 8) {
                    ToggleField(title: "INTERNAL", isOn: $toolpath.operation.threadIsInternal)
                    EnumMenuPicker(title: "HANDEDNESS", selection: $toolpath.operation.threadHandedness)
                }
            }

        case .chamfer:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    NumberField(title: "WIDTH", value: $toolpath.operation.chamferWidth, suffix: "mm")
                    EnumMenuPicker(title: "SIDE", selection: $toolpath.operation.chamferSide)
                    directionPicker
                }
                HStack(spacing: 8) {
                    ToggleField(title: "FIXED DEPTH", isOn: $toolpath.operation.chamferUsesDepth)
                    if toolpath.operation.chamferUsesDepth {
                        NumberField(title: "DEPTH", value: $toolpath.operation.chamferDepth, suffix: "mm")
                    }
                }
            }
        }
    }

    private var directionPicker: some View {
        EnumMenuPicker(title: "DIRECTION", selection: $toolpath.operation.direction)
    }

    /// Ramping gets its own line, since it applies across very different operations.
    /// Once a method (anything other than "None") is chosen, its angle sits right
    /// next to the button — bound to the same `toolpath.ramping.angle` the popover
    /// edits, so the two always agree.
    private var rampingRow: some View {
        HStack(spacing: 8) {
            rampingButton
            if toolpath.ramping.type != .none {
                NumberField(title: "RAMP ANGLE", value: $toolpath.ramping.angle, suffix: "°")
            }
            // Feed while the tool is going down: along the ramp if one is
            // selected, otherwise it's how fast the tool plunges straight in.
            NumberField(title: "RAMP FEED", value: $toolpath.plungeRate, suffix: "mm/min")
                .help(toolpath.ramping.enabled && toolpath.ramping.type != .none
                      ? "Feed rate along the ramp entry."
                      : "No ramping selected — used as the plunge feed rate.")
        }
    }

    private var rampingButton: some View {
        RampingButton(ramping: toolpath.ramping) {
            showRampEditor = true
        }
        .popover(isPresented: $showRampEditor, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
            // A slot steps down by its own depth-per-pass, not by the general stepdown.
            RampingEditor(ramping: $toolpath.ramping,
                          stepdown: kind == .slotting ? toolpath.operation.slotDepthPerPass : toolpath.stepDown)
                .frame(width: 600)
        }
    }
}

// MARK: - Reusable controls

/// A titled menu for any string-backed enum.
struct EnumMenuPicker<Value: Hashable & CaseIterable & RawRepresentable>: View where Value.RawValue == String {
    let title: String
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))

            Picker("", selection: $selection) {
                ForEach(Array(Value.allCases), id: \.self) {
                    Text($0.rawValue)
                        .tag($0)
                }
            }
            .pickerStyle(.menu)
            .frame(height: 30)
        }
    }
}

/// A titled on/off switch, sized like `NumberField`.
struct ToggleField: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))

            HStack {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Text(isOn ? "On" : "Off")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
