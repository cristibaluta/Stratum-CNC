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
}
