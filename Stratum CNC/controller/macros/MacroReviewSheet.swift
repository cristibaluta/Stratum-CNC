//
//  MacroReviewSheet.swift
//  Stratum CNC
//

import SwiftUI
import StratumLink

/// Review before a macro runs, presented from `GCodeViewer`'s "Review & Start..." button while the
/// Macros tab is showing, like `MachiningRunSheet` is for a program. It lists what the macro will
/// do and the macro's checklist; "Start Macro" stays off until every item is ticked. The ticks
/// start empty each time the sheet opens.
struct MacroReviewSheet: View {

    @ObservedObject var model: ControllerModel
    @ObservedObject var store: MacroStore
    @ObservedObject var connection: SL.Connection

    @Environment(\.dismiss) private var dismiss

    @State private var checked: Set<Int> = []

    private var macro: Macro? {
        store.selectedMacro
    }

    private var lines: [String]? {
        guard let macro, case .success(let lines) = store.generate(macro) else {
            return nil
        }
        return lines
    }

    private var machineBusy: Bool {
        connection.isConnected && connection.status?.isBusy == true
    }

    private var canStart: Bool {
        guard let macro, lines != nil else {
            return false
        }
        return connection.isConnected
            && !machineBusy
            && !model.uploader.isActive
            && checked.count == macro.checklist.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let macro {
                VStack(alignment: .leading, spacing: 16) {
                    parametersSection(macro)
                    if !macro.checklist.isEmpty {
                        checklistSection(macro)
                    }
                    if !connection.isConnected {
                        warning("No machine connected")
                    } else if machineBusy {
                        warning("Machine is busy with another job")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }

            Divider()

            footer
        }
        .frame(width: 440)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review & Start")
                    .font(.headline)
                Text(macro?.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
    }

    private func parametersSection(_ macro: Macro) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(macro.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                if store.isXYManual {
                    GridRow {
                        Text("Rapid to X")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(GCodeNumber.string(store.targetXY.x)) mm")
                            .font(.caption.monospacedDigit())
                    }
                    GridRow {
                        Text("Rapid to Y")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(GCodeNumber.string(store.targetXY.y)) mm")
                            .font(.caption.monospacedDigit())
                    }
                }
                ForEach(macro.parameters) { parameter in
                    GridRow {
                        Text(parameter.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(GCodeNumber.string(store.value(parameter, in: macro))) \(parameter.unit)")
                            .font(.caption.monospacedDigit())
                    }
                }
                GridRow {
                    Text("G-code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(lines?.count ?? 0) lines")
                        .font(.caption.monospacedDigit())
                }
            }

            Label(store.isXYManual
                  ? "It first rapids to X and Y at the tool's current height, then Z moves."
                  : "It runs from where the tool is now: X and Y stay, Z moves.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checklistSection(_ macro: Macro) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEFORE YOU START")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(macro.checklist.enumerated()), id: \.offset) { index, item in
                // A button rather than a Toggle: the checkbox style is macOS-only
                Button {
                    if checked.contains(index) {
                        checked.remove(index)
                    } else {
                        checked.insert(index)
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: checked.contains(index) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(checked.contains(index) ? Color.green : Color.secondary)
                        Text(item)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private var footer: some View {
        SheetFooter {
            FooterButton("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        } primary: {
            FooterButton("Start Macro", systemImage: "play.fill") {
                if let lines {
                    model.startJob(lines: lines)
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canStart)
        }
    }
}
