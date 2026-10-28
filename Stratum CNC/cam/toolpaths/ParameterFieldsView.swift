//
//  ParameterFieldsView.swift
//  Stratum CNC
//
//  Renders a `[SC.ParameterField]` -- the form that `SC.MachiningOperation.formFields`
//  builds for whichever operation is chosen -- with the app's own controls
//  (`InspectorNumberField`, `InspectorIntField`, `ToggleField`), one inspector row per field. Nothing here knows about a specific
//  operation: what appears, in which order and with which range is decided entirely by
//  the fields it is given, so a new operation or parameter in `formFields` shows up
//  without touching any view code.
//

import SwiftUI
import StratumCAM

struct ParameterFieldsView: View {
    let fields: [SC.ParameterField]

    /// Field ids the app doesn't offer (yet). Matched at every nesting depth.
    var hiddenFieldIDs: Set<String> = []

    /// Variant case ids the app doesn't offer (yet), e.g. an engine path that isn't implemented.
    var hiddenCaseIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            ForEach(visibleFields) { field in
                fieldView(field)
            }
        }
    }

    private var visibleFields: [SC.ParameterField] {
        fields.filter { !hiddenFieldIDs.contains($0.id) }
    }

    /// Tooltips for the on/off fields whose label alone doesn't say what they do, by field id.
    private static let helpTexts: [String: String] = [
        "boring.shiftRetract": "Before pulling the tool out, move it sideways off the bore wall, so the retract doesn't drag along the finished surface and leave a mark.",
        "boring.dwellTime": "Pause at the bottom of the bore before retracting, so the tool finishes cutting a full circle.",
        "chamfer.params.depth": "Cut to this depth instead of the one the V-bit's angle gives for the width."
    ]

    // MARK: Simple fields

    @ViewBuilder
    private func leafView(_ field: SC.ParameterField) -> some View {
        switch field {
            case .double(let f):
                InspectorNumberField(title: f.label,
                                     value: Binding(get: { f.value },
                                                    set: { f.onChange(clamp($0, to: f.range)) }),
                                     suffix: f.unit ?? "")
                    .disabled(!f.isEnabled)
                    .opacity(f.isEnabled ? 1 : 0.5)
            case .int(let f):
                InspectorIntField(title: f.label,
                                  value: Binding(get: { f.value },
                                                 set: { f.onChange(clamp($0, to: f.range)) }),
                                  suffix: "")
            case .bool(let f):
                ToggleField(title: f.label,
                            isOn: Binding(get: { f.value }, set: { f.onChange($0) }),
                            help: Self.helpTexts[f.id])
            case .choice(let f) where f.isCutDirection:
                // Climb / conventional: a segmented control, same as the contour side.
                DirectionPicker(direction: Binding(get: { f.cutDirection },
                                                   set: { f.onChange($0.fieldID) }))
            case .choice(let f):
                ChoiceControl(title: f.label,
                              options: f.options,
                              selectedID: f.selectedId,
                              onSelect: f.onChange)
            default:
                EmptyView()
        }
    }

    // MARK: Fields with content of their own

    @ViewBuilder
    private func fieldView(_ field: SC.ParameterField) -> some View {
        switch field {

            case .optionalDouble(let f):
                // A switch ("Use peck depth"), and the value under the field's own label once it's on.
                ToggleField(title: "Use \(f.label.lowercased())",
                            isOn: Binding(get: { f.value != nil },
                                          set: { f.onChange($0 ? f.defaultValueWhenEnabled : nil) }),
                            help: Self.helpTexts[f.id])
                if let value = f.value {
                    InspectorNumberField(title: f.label,
                                         value: Binding(get: { value },
                                                        set: { f.onChange(clamp($0, to: f.range)) }),
                                         suffix: f.unit ?? "")
                }

            case .variant(let f):
                let visibleCases = f.cases.filter { !hiddenCaseIDs.contains($0.id) }
                ChoiceControl(title: f.label,
                              options: visibleCases.map { .init(id: $0.id, label: $0.label) },
                              selectedID: f.selectedId,
                              onSelect: f.onSelect)
                if let selected = f.cases.first(where: { $0.id == f.selectedId }), !selected.fields.isEmpty {
                    nested(selected.fields)
                }

            case .group(let f):
                subheader(f.label)
                nested(f.fields)

            case .optionalGroup(let f):
                ToggleField(title: f.label,
                            isOn: Binding(get: { f.isPresent }, set: { f.onToggle($0) }))
                if f.isPresent {
                    nested(f.fields)
                }

            case .row(let f):
                // Rows were side by side fields (e.g. diameter + pitch); the inspector
                // gives each its own labelled row.
                ForEach(f.fields) { field in
                    leafView(field)
                }

            case .list(let f):
                HStack {
                    subheader(f.label)
                    Spacer()
                    Button {
                        f.onAdd()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                ForEach(f.items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        nested(item.fields)
                        Button {
                            f.onRemove(item.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                }

            default:
                leafView(field)
        }
    }

    private func nested(_ fields: [SC.ParameterField]) -> some View {
        ParameterFieldsView(fields: fields,
                            hiddenFieldIDs: hiddenFieldIDs,
                            hiddenCaseIDs: hiddenCaseIDs)
    }

    private func subheader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.top, 4)
    }

    // MARK: Helpers

    /// The ranges in `formFields` are the limits the engine accepts, so a typed value is
    /// pulled back inside them instead of being passed on.
    private func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Cut direction

private extension SC.ParameterField.ChoiceField {

    /// True for the climb / conventional choice built by `SC.cutDirectionChoice`. Matched on
    /// its options rather than its id, so every operation's direction field -- contour,
    /// pocket, facing, counterbore, chamfer -- gets the glyph picker, while thread
    /// handedness and spiral direction keep the plain menu.
    var isCutDirection: Bool {
        options.map(\.id) == [SC.CutDirection.climb.rawValue, SC.CutDirection.conventional.rawValue]
    }

    var cutDirection: CutDirectionOption {
        selectedId == SC.CutDirection.conventional.rawValue ? .conventional : .climb
    }
}

private extension CutDirectionOption {
    var fieldID: String {
        switch self {
            case .climb:        return SC.CutDirection.climb.rawValue
            case .conventional: return SC.CutDirection.conventional.rawValue
        }
    }
}

// MARK: - Choice

/// A labelled pop-up button choosing between string-identified options. The cut
/// direction is the exception: see `DirectionPicker`.
struct ChoiceControl: View {
    let title: String
    let options: [SC.ParameterField.ChoiceField.Option]
    let selectedID: String
    let onSelect: (String) -> Void

    var body: some View {
        InspectorRow(label: title) {
            Menu {
                ForEach(options) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        if option.id == selectedID {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                InspectorMenuLabel {
                    Text(selectedLabel)
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
    }

    private var selectedLabel: String {
        options.first(where: { $0.id == selectedID })?.label ?? ""
    }
}
