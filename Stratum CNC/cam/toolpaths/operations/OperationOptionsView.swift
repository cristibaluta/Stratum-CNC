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

    /// When true, every picker below lays its options out directly in the
    /// view instead of behind a button + popover or a menu.
    var expanded: Bool = false

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
            VStack(alignment: .leading, spacing: 8) {
                row {
                    ContourPicker(selection: $toolpath.contour, expanded: expanded)
                    directionPicker
                }
                Divider()
                rampingRow
            }

        case .pocket:
            VStack(alignment: .leading, spacing: 8) {
                row {
                    PatternPicker(pattern: $toolpath.operation.pocketPattern, expanded: expanded)
                    directionPicker
                }
                switch toolpath.operation.pocketPattern {
                    case .spiral:
                        HStack(spacing: 8) {
                            EnumMenuPicker(title: "SPIRAL", selection: $toolpath.operation.pocketSpiral, expanded: expanded)
                        }
                    case .trochoidal:
                        HStack(spacing: 8) {
                            NumberField(title: "LOOP PITCH", value: $toolpath.operation.pocketTrochoidalPitch, suffix: "% radius")
                        }
                    case .offset, .raster:
                        EmptyView()
                }
                Divider()
                rampingRow
            }

        case .facing:
            row {
                directionPicker
                NumberField(title: "EXTENSION", value: $toolpath.operation.facingExtension, suffix: "mm")
            }

        case .slotting:
            VStack(alignment: .leading, spacing: 8) {
                row {
                    EnumMenuPicker(title: "SELECTION IS", selection: $toolpath.operation.slotSource, expanded: expanded)
                    NumberField(title: "DEPTH / PASS", value: $toolpath.operation.slotDepthPerPass, suffix: "mm")
                }
                Divider()
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    NumberField(title: "DIAMETER", value: $toolpath.operation.counterboreDiameter, suffix: "mm")
                    NumberField(title: "DEPTH", value: $toolpath.operation.counterboreDepth, suffix: "mm")
                }
                HStack(spacing: 8) {
                    directionPicker
                }
                Divider()
                rampingRow
            }

        case .boring:
            VStack(alignment: .leading, spacing: 8) {
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    NumberField(title: "PITCH", value: $toolpath.operation.threadPitch, suffix: "mm")
                    NumberField(title: "THREAD Ø", value: $toolpath.operation.threadTargetDiameter, suffix: "mm")
                    IntField(title: "RADIAL PASSES", value: $toolpath.operation.threadRadialPasses, suffix: "")
                }
                row {
                    ToggleField(title: "INTERNAL", isOn: $toolpath.operation.threadIsInternal)
                    EnumMenuPicker(title: "HANDEDNESS", selection: $toolpath.operation.threadHandedness, expanded: expanded)
                }
            }

        case .chamfer:
            VStack(alignment: .leading, spacing: 8) {
                row {
                    NumberField(title: "WIDTH", value: $toolpath.operation.chamferWidth, suffix: "mm")
                    EnumMenuPicker(title: "SIDE", selection: $toolpath.operation.chamferSide, expanded: expanded)
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
        DirectionPicker(direction: $toolpath.operation.direction, expanded: expanded)
    }

    /// A row of controls, side by side when compact. Expanded pickers need
    /// their full width to lay out their options directly, so the same row
    /// stacks vertically once expanded.
    @ViewBuilder
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if expanded {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        } else {
            HStack(spacing: 8) {
                content()
            }
        }
    }

    /// Ramping gets its own line, since it applies across very different operations.
    /// Once a method (anything other than "None") is chosen, its angle sits right
    /// next to the button — bound to the same `toolpath.ramping.angle` the popover
    /// edits, so the two always agree.
    private var rampingRow: some View {
        row {
            rampingButton
            HStack {
                if toolpath.ramping.type != .none {
                    NumberField(title: "RAMP ANGLE", value: $toolpath.ramping.angle, suffix: "°")
                }

                NumberField(title: "RAMP FEED", value: $toolpath.plungeRate, suffix: "mm/min")
                    .help(toolpath.ramping.enabled && toolpath.ramping.type != .none
                          ? "Feed rate along the ramp entry."
                          : "No ramping selected — used as the plunge feed rate.")
            }
        }
    }

    private var rampingButton: some View {
        RampingButton(ramping: $toolpath.ramping, expanded: expanded) {
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

/// A titled menu for any string-backed enum. In its expanded form, every
/// case is laid out as a row of pill buttons instead of behind a menu.
struct EnumMenuPicker<Value: Hashable & CaseIterable & RawRepresentable>: View where Value.RawValue == String {
    let title: String
    @Binding var selection: Value
    var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))

            if expanded {
                HStack(spacing: 6) {
                    ForEach(Array(Value.allCases), id: \.self) { option in
                        pill(for: option)
                    }
                }
            } else {
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

    private func pill(for option: Value) -> some View {
        let isSelected = option == selection

        return Button {
            selection = option
        } label: {
            Text(option.rawValue)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
