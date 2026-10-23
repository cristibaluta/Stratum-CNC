//
//  MacroDetailView.swift
//  Stratum CNC
//

import SwiftUI
import AppKit

/// Parameters and run button for the selected macro. Shown between the macro
/// list and the G-code table, which displays the macro's generated G-code.
struct MacroDetailView: View {

    @ObservedObject var store: MacroStore
    let macro: Macro
    let canRun: Bool
    let onRun: ([String]) -> Void

    @State private var isConfirmingRun = false

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

            switch result {
                case .failure(let error):
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                case .success(let lines):
                    HStack {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        Spacer()

                        Button {
                            isConfirmingRun = true
                        } label: {
                            Label("Run Macro", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canRun)
                        .help(canRun ? "Run at the current tool position" : "Connect an idle machine to run")
                    }
                    .confirmationDialog("Run \(macro.name)?",
                                        isPresented: $isConfirmingRun,
                                        titleVisibility: .visible) {
                        Button("Run at current position") { onRun(lines) }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The machine will move from where the tool is now.")
                    }
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .cornerRadius(8)
    }
}
