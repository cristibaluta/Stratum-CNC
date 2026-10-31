//
//  ManageImportsView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 31.10.2026.
//
//
//  Lists every import batch with its date and tool count, and lets you remove a whole batch.
//  Removing is a live edit (see `ToolsStore.removeImport`): nothing is written to disk until
//  Save, and Revert in the library's bottom bar brings the batch back.
//

import SwiftUI

struct ManageImportsView: View {

    @ObservedObject var store: ToolsStore

    @Environment(\.dismiss) private var dismiss

    @State private var batchPendingRemoval: ToolSourceInfo?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.importSources.isEmpty {
                ContentUnavailableView(
                    "No Imports",
                    systemImage: "square.and.arrow.down",
                    description: Text("Tools you import from a Fusion 360 library show up here, one batch per file.")
                )
            } else {
                List(store.importSources) { batch in
                    BatchRow(batch: batch, toolCount: store.toolCount(in: batch)) {
                        batchPendingRemoval = batch
                    }
                }
            }

            Divider()
            footer
        }
        .frame(width: 480, height: 360)
        .confirmationDialog(
            "Remove \"\(batchPendingRemoval?.name ?? "")\"?",
            isPresented: Binding(
                get: { batchPendingRemoval != nil },
                set: { if !$0 { batchPendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: batchPendingRemoval
        ) { batch in
            Button("Remove \(Self.toolsText(store.toolCount(in: batch)))", role: .destructive) {
                store.removeImport(batch)
            }
        } message: { batch in
            Text("This removes \(Self.toolsText(store.toolCount(in: batch))) that came from this import. You can undo it with Revert until you save.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Manage Imports")
                .font(.headline)
            Text("Removing a batch removes every tool that was added by that import.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            if store.hasUnsavedChanges {
                Text("Unsaved changes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private static func toolsText(_ count: Int) -> String {
        count == 1 ? "1 tool" : "\(count) tools"
    }
}

// MARK: - Row

private struct BatchRow: View {

    let batch: ToolSourceInfo
    let toolCount: Int
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(batch.name)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Remove Batch", role: .destructive, action: onRemove)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    /// "14 tools · Imported 31 Oct 2026"
    private var detail: String {
        var parts = [toolCount == 1 ? "1 tool" : "\(toolCount) tools"]
        if let date = batch.date {
            parts.append("Imported \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}
