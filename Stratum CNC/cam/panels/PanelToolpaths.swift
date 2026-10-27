//
//  ToolpathListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct PanelToolpaths: View {

    @Binding var toolpaths: [ToolpathData]
    let selectedID: UUID?
    var hiddenIDs: Set<UUID> = []

    var onSelect: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onAdd: (() -> Void)?

    @State private var draggedToolpath: ToolpathData?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorHeader(title: "Toolpaths", addHelp: "Add a toolpath") {
                onAdd?()
            }

            Divider()

            if toolpaths.isEmpty {
                Text("No toolpaths")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(toolpaths) { toolpath in
                        toolpathRow(toolpath)
                            .onDrag {
                                draggedToolpath = toolpath
                                return NSItemProvider(object: toolpath.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text],
                                    delegate: ToolpathDropDelegate(target: toolpath,
                                                                   toolpaths: $toolpaths,
                                                                   draggedToolpath: $draggedToolpath))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Row

    private func toolpathRow(_ toolpath: ToolpathData) -> some View {
        let isSelected = toolpath.id == selectedID
        let isHidden = hiddenIDs.contains(toolpath.id)

        return HStack(spacing: 8) {
            Image(systemName: toolpath.operation.kind.symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .opacity(isHidden ? 0.5 : 1)

            Button {
                onSelect?(toolpath.id)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(toolpath.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text("\(toolpath.operation.kind.title) · \(toolpath.tool.name)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .opacity(isHidden ? 0.5 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            InspectorVisibilityButton(isVisible: !isHidden,
                                      showHelp: "Show on canvas",
                                      hideHelp: "Hide from canvas") {
                onToggleVisibility?(toolpath.id)
            }
        }
        .inspectorListRow(isSelected: isSelected)
        .contextMenu {
            Button(role: .destructive) {
                onDelete?(toolpath.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
