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

    private var kind: OperationKind {
        toolpath.operation.kind
    }

    var body: some View {
        let fields = toolpath.machiningOperation.formFields { toolpath.machiningOperation = $0 }

        VStack(alignment: .leading, spacing: 8) {
            if kind == .slotting {
                EnumMenuPicker(title: "SELECTION IS", selection: $toolpath.operation.slotSource, expanded: expanded)
            }

            // Which side of the boundary the tool follows -- same glyph-based picker
            // for both, since `ContourPicker` is generic over `CutSideOption`.
            if kind == .contour {
                ContourPicker(selection: $toolpath.contour, title: "CONTOUR", expanded: expanded)
            } else if kind == .chamfer {
                ContourPicker(selection: $toolpath.operation.chamferSide, expanded: expanded)
            }

            ParameterFieldsView(fields: fields,
                                expanded: expanded,
                                hiddenFieldIDs: kind.hiddenFieldIDs,
                                hiddenCaseIDs: OperationKind.hiddenCaseIDs)

            // The clearing pattern keeps its own dedicated picker (icon glyphs, same as
            // `ContourTypeGlyph`), same idea as the entry strategy below.
            if kind == .pocket {
                Divider()
                patternRow
            }

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

    /// Same picker `PatternPicker` already offers elsewhere: a glyph per pattern (rings,
    /// scanlines, spiral, loops) instead of the generic engine field's text-only menu.
    private var patternRow: some View {
        row {
            PatternPicker(pattern: $toolpath.operation.pocketPattern, expanded: expanded)
            patternDetail
        }
    }

    /// The one extra control a pattern needs, if any -- which way a spiral winds in,
    /// or how tightly a trochoidal loop steps forward. Both are only stored on
    /// `OperationSettings`, not exposed by the generic form once `pattern` is hidden.
    @ViewBuilder
    private var patternDetail: some View {
        switch toolpath.operation.pocketPattern {
            case .spiral:
                EnumMenuPicker(title: "SPIRAL DIRECTION", selection: $toolpath.operation.pocketSpiral, expanded: expanded)
            case .trochoidal:
                NumberField(title: "LOOP PITCH", value: $toolpath.operation.pocketTrochoidalPitch, suffix: "% radius")
            case .offset, .raster:
                EmptyView()
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
            // The side gets its own dedicated `ContourPicker` row above; lead-in/out
            // and tabs aren't stored on the toolpath.
            return ["entry", "contour.side", "contour.leadIn", "contour.leadOut", "contour.tabs"]
        case .pocket:
            // The clearing pattern gets its own dedicated row (`patternRow`) with icon
            // glyphs, so the generic text-only field is hidden entirely, spiral direction
            // and trochoidal pitch included.
            return ["entry", "pattern"]
        case .slotting:
            // Only `.raster` makes sense until open-ended slots are derived.
            return ["entry", "pattern"]
        case .counterbore:
            return ["entry"]
        case .chamfer:
            // The side gets its own dedicated `ContourPicker` row above.
            return ["chamfer.params.side"]
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
