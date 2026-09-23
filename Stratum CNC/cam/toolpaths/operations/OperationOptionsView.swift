//
//  OperationOptionsView.swift
//  Stratum CNC
//
//  The row of controls that changes with the chosen operation: a contour has a side, a
//  drill has an optional peck depth, a counterbore has a diameter and a depth…
//

import SwiftUI
import StratumCAM

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

    /// The fields come straight from `SC.MachiningOperation.formFields`, so which controls
    /// an operation has -- and their labels, ranges and nesting -- is defined there, not here.
    /// Edits flow back through `ToolpathData.machiningOperation`.
    @ViewBuilder
    private var options: some View {
        let fields = toolpath.machiningOperation.formFields { toolpath.machiningOperation = $0 }

        VStack(alignment: .leading, spacing: 8) {

            // What the selected shape means isn't part of the engine's operation: the
            // app turns a slot outline into the centre line the engine wants.
            if kind == .slotting {
                EnumMenuPicker(title: "SELECTION IS", selection: $toolpath.operation.slotSource, expanded: expanded)
            }

            ParameterFieldsView(fields: fields,
                                expanded: expanded,
                                hiddenFieldIDs: kind.hiddenFieldIDs,
                                hiddenCaseIDs: OperationKind.hiddenCaseIDs)

            // The entry strategy keeps its dedicated editor (angle/length preview, helix
            // diagram), but whether an operation has one is still up to `formFields`.
            if fields.contains(where: { $0.id == "entry" }) {
                Divider()
                rampingRow
            }
        }
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

// MARK: - What the app doesn't offer (yet)

private extension OperationKind {

    /// `formFields` describes everything the engine can take. These parts have no home in
    /// `ToolpathData` yet, or are covered by another control.
    var hiddenFieldIDs: Set<String> {
        switch self {
        case .contour:
            // Lead-in/out and tabs aren't stored on the toolpath.
            return ["entry", "contour.leadIn", "contour.leadOut", "contour.tabs"]
        case .pocket:
            // The pocket ignores the trochoidal loop radius (see makePocketPattern).
            return ["entry", "pattern.trochoidal.loopRadius"]
        case .slotting:
            // Only `.raster` makes sense until open-ended slots are derived.
            return ["entry", "pattern"]
        case .counterbore:
            return ["entry"]
        default:
            return []
        }
    }

    /// `.adaptive` pockets crash the engine (`fatalError`), `.fromOpenEnd` entry needs an
    /// open slot outline.
    static let hiddenCaseIDs: Set<String> = ["adaptive", "fromOpenEnd"]
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
