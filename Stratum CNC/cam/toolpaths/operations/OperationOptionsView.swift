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

    @State private var showRampEditor = false

    private var kind: OperationKind {
        toolpath.operation.kind
    }

    /// What the library says the operation takes and accepts; every optional row below is
    /// shown because of it, not because of the operation's kind.
    private var requirements: SC.OperationRequirements {
        toolpath.machiningOperation.requirements
    }

    /// The patterns to offer in the pattern row: the pocket's. A slot has patterns of its own
    /// (`requirements.slotPatterns`), which the app doesn't offer until open-ended slots can
    /// be derived from the drawing.
    private var offeredPatterns: [PocketPattern] {
        requirements.pocketPatterns.map { PocketPattern($0) }
    }

    var body: some View {
        let fields = toolpath.machiningOperation.formFields { toolpath.machiningOperation = $0 }

        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            if kind == .slotting {
                EnumMenuPicker(title: "Selection is", selection: $toolpath.operation.slotSource)
            }

            // Which side of the boundary the tool follows -- same glyph-based picker
            // for both, since `ContourPicker` is generic over `CutSideOption`.
            if kind == .contour {
                ContourPicker(selection: $toolpath.contour, title: "Side")
            } else if kind == .chamfer {
                ContourPicker(selection: $toolpath.operation.chamferSide)
            }

            ParameterFieldsView(fields: fields,
                                hiddenFieldIDs: kind.hiddenFieldIDs,
                                hiddenCaseIDs: OperationKind.hiddenCaseIDs)

            // The clearing pattern keeps its own dedicated picker (icon glyphs, same as
            // `ContourTypeGlyph`), same idea as the entry strategy below.
            if !offeredPatterns.isEmpty {
                patternRow
            }

            // The entry strategy keeps its dedicated editor (angle/length preview, helix
            // diagram), but whether an operation has one is up to the library.
            if requirements.usesEntry {
                rampingRow
            }
        }
        // The ramping settings are shared by every operation, so one left over from another
        // operation (a helix, say) may be one this operation can't use.
        .onAppear { normalizeRampType() }
        .onChange(of: kind) { _, _ in normalizeRampType() }
    }

    /// The ramp types the operation accepts, taken from the entry strategies the library
    /// offers for it (an engraving has no helix, for instance).
    private var availableRampTypes: [RampType] {
        var types: [RampType] = []
        for entry in requirements.entries {
            switch entry {
                case .plunge:      types.append(.none)
                case .ramp:        types.append(.linear)
                case .helix:       types.append(.helix)
                case .fromOpenEnd: break   // not offered by the app, see `OperationKind.hiddenCaseIDs`
            }
        }
        return types
    }

    /// Switches a ramp type the operation doesn't accept to the closest one it does: a
    /// helix becomes a linear ramp at the same angle.
    private func normalizeRampType() {
        let available = availableRampTypes
        guard requirements.usesEntry,
              !available.isEmpty,
              !available.contains(toolpath.ramping.type) else {
            return
        }
        toolpath.ramping.type = available.contains(.linear) ? .linear : .none
    }

    /// Ramping gets its own rows, since it applies across very different operations.
    /// Once a method (anything other than "None") is chosen, its angle sits right
    /// below the button -- bound to the same `toolpath.ramping.angle` the popover
    /// edits, so the two always agree.
    @ViewBuilder
    private var rampingRow: some View {
        rampingButton
        if toolpath.ramping.type != .none {
            InspectorNumberField(title: "Ramp angle", value: $toolpath.ramping.angle, suffix: "°")
        }
        InspectorNumberField(title: "Ramp feed", value: $toolpath.plungeRate, suffix: "mm/min")
            .help(toolpath.ramping.enabled && toolpath.ramping.type != .none
                  ? "Feed rate along the ramp entry."
                  : "No ramping selected — used as the plunge feed rate.")
    }

    private var rampingButton: some View {
        RampingButton(ramping: $toolpath.ramping, available: availableRampTypes) {
            showRampEditor = true
        }
        .popover(isPresented: $showRampEditor, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
            // A slot steps down by its own depth-per-pass, not by the general stepdown.
            RampingEditor(ramping: $toolpath.ramping,
                          stepdown: kind == .slotting ? toolpath.operation.slotDepthPerPass : toolpath.stepDown,
                          toolDiameter: Double(toolpath.tool.toolDiameter),
                          available: availableRampTypes)
                .frame(width: 400)
        }
    }

    @ViewBuilder
    private var patternRow: some View {
        PatternPicker(pattern: $toolpath.operation.pocketPattern, available: offeredPatterns)
        patternDetail
    }

    /// The one extra control a pattern needs, if any -- which way a spiral winds in,
    /// how tightly a trochoidal loop steps forward, or how much of the tool an adaptive
    /// pass is allowed to bury in the material. These are only stored on
    /// `OperationSettings`, not exposed by the generic form once `pattern` is hidden.
    @ViewBuilder
    private var patternDetail: some View {
        switch toolpath.operation.pocketPattern {
            case .spiral, .concentric:
                EnumMenuPicker(title: "Spiral direction", selection: $toolpath.operation.pocketSpiral)
            case .trochoidal:
                InspectorNumberField(title: "Loop pitch", value: $toolpath.operation.pocketTrochoidalPitch, suffix: "% radius")
            case .adaptive:
                InspectorNumberField(title: "Optimal load", value: $toolpath.operation.pocketAdaptiveLoad, suffix: "mm")
                    .help("Radial engagement the tool is kept at while clearing. Smaller values mean lighter cuts and more passes.")
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
        case .engrave:
            // Same dedicated ramping row as the other operations with an entry.
            return ["entry"]
        case .chamfer:
            // The side gets its own dedicated `ContourPicker` row above.
            return ["chamfer.params.side"]
        default:
            return []
        }
    }

    static let hiddenCaseIDs: Set<String> = ["adaptive", "fromOpenEnd"]
}

// MARK: - Reusable controls

/// A labelled pop-up button for any string-backed enum.
struct EnumMenuPicker<Value: Hashable & CaseIterable & RawRepresentable>: View where Value.RawValue == String {
    let title: String
    @Binding var selection: Value

    var body: some View {
        InspectorRow(label: title) {
            Menu {
                ForEach(Array(Value.allCases), id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        if option == selection {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                InspectorMenuLabel {
                    Text(selection.rawValue)
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
    }
}

/// A labelled on/off switch.
struct ToggleField: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        InspectorRow(label: title) {
            HStack(spacing: 8) {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Text(isOn ? "On" : "Off")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
