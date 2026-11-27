//
//  MacroDetailView.swift
//  Stratum CNC
//

import SwiftUI

/// Parameters of the selected macro. Shown between the macro list and the G-code table, which
/// displays the macro's generated G-code. Running it is the "Review & Start..." button under the
/// table, which opens `MacroReviewSheet`.
struct MacroDetailView: View {

    @ObservedObject var store: MacroStore
    let macro: Macro

    var body: some View {
        let result = store.generate(macro)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(macro.name)
                    .font(.headline)
                Spacer()
                Button {
                    store.reset(macro)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset parameters to defaults")
            }

            Text(macro.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                positionRow("X", binding: store.xBinding)
                positionRow("Y", binding: store.yBinding)

                ForEach(macro.parameters) { parameter in
                    GridRow {
                        Text(parameter.label)
                            .font(.caption)
                            .lineLimit(1)
                        TextField("", value: store.binding(parameter, in: macro), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text(parameter.unit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(store.isXYManual
                 ? "The macro starts with a rapid (G0) to X/Y."
                 : "X/Y follow the tool. Type a value to go there instead.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if case .failure(let error) = result {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .cornerRadius(8)
    }

    /// X or Y of the hole. Shows the tool's position until a value is typed in; the button next to
    /// it goes back to following the tool.
    private func positionRow(_ axis: String, binding: Binding<Double>) -> some View {
        GridRow {
            Text("Position \(axis)")
                .font(.caption)
                .lineLimit(1)
            TextField("", value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            HStack(spacing: 4) {
                Text("mm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if axis == "Y" {
                    Button {
                        store.useCurrentXY()
                    } label: {
                        Image(systemName: "scope")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!store.isXYManual)
                    .help("Use the tool's current position")
                }
            }
        }
    }
}
