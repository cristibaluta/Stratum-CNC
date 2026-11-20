//
//  ToolParametersMatrix.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 27.08.2026.
//

import SwiftUI

/// Editable table of a tool's cutting presets, shown alphabetically by name.
struct ToolParametersMatrix: View {
    @Binding var presets: [ToolPreset]

    private let columns = [
        GridItem(.fixed(120), alignment: .leading),
        GridItem(.flexible(), alignment: .trailing),
        GridItem(.flexible(), alignment: .trailing),
        GridItem(.flexible(), alignment: .trailing),
        GridItem(.flexible(), alignment: .trailing),
        GridItem(.flexible(), alignment: .trailing)
    ]

    /// Ids in alphabetical order by preset name.
    private var sortedIDs: [UUID] {
        presets
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 0) {

                // Header
                headerCell("Material", alignment: .leading)
                headerCell("Spindle RPM")
                headerCell("Feed Rate")
                headerCell("Plunge Feed")
                headerCell("Depth of Cut")
                headerCell("Ramp Angle")

                // Rows
                ForEach(sortedIDs, id: \.self) { id in
                    row(for: binding(for: id), id: id)
                }
            }

            Button {
                presets.append(ToolPreset(name: "New Preset"))
            } label: {
                Label("Add Preset", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for preset: Binding<ToolPreset>, id: UUID) -> some View {
        let delete = { presets.removeAll { $0.id == id } }

        PresetNameField(name: preset.name)
            .modifier(CellStyle(alignment: .leading, onDelete: delete))

        integerField(preset.spindleRPM, onDelete: delete)
        numberField(preset.feedRate, onDelete: delete)
        numberField(preset.plungeFeedRate, onDelete: delete)
        numberField(preset.depthOfCut, onDelete: delete)
        numberField(preset.rampAngle, onDelete: delete)
    }

    /// A binding to one preset that stays safe if the row disappears (e.g. while it is deleted).
    private func binding(for id: UUID) -> Binding<ToolPreset> {
        Binding(
            get: { presets.first { $0.id == id } ?? ToolPreset(id: id, name: "") },
            set: { newValue in
                if let index = presets.firstIndex(where: { $0.id == id }) {
                    presets[index] = newValue
                }
            }
        )
    }

    // MARK: - Cells

    private func numberField(_ value: Binding<Double?>, onDelete: @escaping () -> Void) -> some View {
        TextField("", value: value,
                  format: FloatingPointFormatStyle<Double>().grouping(.never),
                  prompt: Text("–"))
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .modifier(CellStyle(alignment: .trailing, onDelete: onDelete))
    }

    private func integerField(_ value: Binding<Int?>, onDelete: @escaping () -> Void) -> some View {
        TextField("", value: value,
                  format: IntegerFormatStyle<Int>().grouping(.never),
                  prompt: Text("–"))
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .modifier(CellStyle(alignment: .trailing, onDelete: onDelete))
    }

    private func headerCell(_ text: String, alignment: Alignment = .trailing) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.vertical, 10)
    }
}

private struct CellStyle: ViewModifier {
    let alignment: Alignment
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Divider()
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("Delete Preset", systemImage: "trash", role: .destructive, action: onDelete)
            }
    }
}

/// Edits the name on a draft and commits on Return or when focus leaves the field.
/// Rows are sorted by name, so committing per keystroke would move the row
/// away from under the cursor while typing.
private struct PresetNameField: View {
    @Binding var name: String

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        // Inside a Form a TextField's title is drawn as a leading label, so hide it
        // and use a prompt (placeholder) instead.
        TextField("", text: $draft, prompt: Text("Name"))
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onAppear { draft = name }
            .onChange(of: name) { _, newValue in
                if !isFocused {
                    draft = newValue
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commit()
                }
            }
            .onSubmit(commit)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            draft = name                // don't allow an empty name
        } else if trimmed != name {
            name = trimmed
        }
    }
}
