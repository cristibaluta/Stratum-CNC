//
//  ToolsSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct ToolsSheet: View {

    @ObservedObject var store: ToolsStore
    @State private var selectedToolID: Tool.ID?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationSplitView {
            ToolListView(tools: store.tools, selectedToolID: $selectedToolID)
                .navigationSplitViewColumnWidth(200)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        } detail: {
            if let selectedToolID,
               let index = store.tools.firstIndex(where: { $0.id == selectedToolID }) {
                ToolEditorView(
                    tool: Binding(
                        get: {
                            store.tools[index]
                        },
                        set: { newValue in
                            store.tools[index] = newValue

                            do {
                                try store.save()
                            } catch {
                                print("Failed to save tool: \(error)")
                            }
                        }
                    )
                )
            } else {
                ContentUnavailableView(
                    "No Tool Selected",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Select a tool from the list.")
                )
            }
        }
        .navigationTitle("Tools")
    }
}
